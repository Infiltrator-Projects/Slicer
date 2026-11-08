// SPDX-License-Identifier: AGPL-3.0-or-later
// Native C++17 regression for ownership protections in build-deb.sh.
// Uses disposable fixtures and a stub CMake executable, never a real build.
#include <cerrno>
#include <chrono>
#include <csignal>
#include <cstdlib>
#include <cstring>
#include <filesystem>
#include <fstream>
#include <iostream>
#include <iterator>
#include <stdexcept>
#include <string>
#include <thread>
#include <vector>
#include <sys/types.h>
#include <sys/wait.h>
#include <unistd.h>
namespace fs=std::filesystem;
static void require(bool valid,const std::string& why){
    if(!valid)throw std::runtime_error(why);
}
static void write(const fs::path& path,const std::string& bytes,bool executable=false){
    fs::create_directories(path.parent_path());
    std::ofstream file(path,std::ios::binary|std::ios::trunc);
    require(bool(file),"cannot open fixture "+path.string());
    file<<bytes;
    file.close();
    require(bool(file),"cannot write fixture "+path.string());
    if(executable)fs::permissions(path,fs::perms::owner_exec|fs::perms::group_exec|
                                       fs::perms::others_exec,fs::perm_options::add);
}
static std::string read(const fs::path& path){
    std::ifstream file(path,std::ios::binary);
    require(bool(file),"missing fixture "+path.string());
    return {std::istreambuf_iterator<char>(file),std::istreambuf_iterator<char>()};
}
struct Scratch{
    fs::path root;
    Scratch(){
        auto name=(fs::temp_directory_path()/"slicer-build-root-XXXXXX").string();
        std::vector<char> writable(name.begin(),name.end());writable.push_back('\0');
        auto* made=mkdtemp(writable.data());
        require(made!=nullptr,"cannot allocate disposable regression directory");
        root=fs::canonical(made);
    }
    ~Scratch(){std::error_code ec;if(!root.empty())fs::remove_all(root,ec);}
    Scratch(const Scratch&)=delete;
    Scratch& operator=(const Scratch&)=delete;
};
static int run(const fs::path& source,const fs::path& script,const fs::path& binary,
               const fs::path& log,const fs::path& build_root,bool clean){
    const char* env_path=std::getenv("PATH");
    require(env_path!=nullptr,"PATH unavailable");
    const std::string path=binary.string()+":"+env_path;
    const pid_t child=fork();
    require(child>=0,"fork failed");
    if(child==0){
        const int old_out=dup(STDOUT_FILENO);
        (void)old_out;
        if(chdir(source.c_str())!=0)_exit(127);
        if(setenv("PATH",path.c_str(),1)!=0||
           setenv("FIXTURE_LOG",log.c_str(),1)!=0)_exit(127);
        const auto script_name=script.string();
        const auto build_name=build_root.string();
        const int fd=open("/dev/null",O_WRONLY);
        if(fd>=0){
            dup2(fd,STDOUT_FILENO);
            dup2(fd,STDERR_FILENO);
            close(fd);
        }
        if(clean)
            execl("/bin/bash","bash",script_name.c_str(),"--build-root",
                  build_name.c_str(),"--clean",static_cast<char*>(nullptr));
        else
            execl("/bin/bash","bash",script_name.c_str(),"--build-root",
                  build_name.c_str(),static_cast<char*>(nullptr));
        _exit(127);
    }
    const auto deadline=std::chrono::steady_clock::now()+std::chrono::seconds(30);
    int status=0;
    while(true){
        const auto waited=waitpid(child,&status,WNOHANG);
        if(waited==child)break;
        if(waited<0){
            if(errno==EINTR)continue;
            kill(child,SIGKILL);
            while(waitpid(child,&status,0)<0&&errno==EINTR){}
            throw std::runtime_error("waitpid failed");
        }
        if(std::chrono::steady_clock::now()>=deadline){
            kill(child,SIGKILL);
            while(waitpid(child,&status,0)<0&&errno==EINTR){}
            throw std::runtime_error("build-root policy test timed out");
        }
        std::this_thread::sleep_for(std::chrono::milliseconds(10));
    }
    return WIFEXITED(status)?WEXITSTATUS(status):128+WTERMSIG(status);
}
int main(int argc,char**argv){
    try{
        require(argc==2,"Usage: verify-build-root PATH_TO_BUILD_DEB_SH");
        const auto script=fs::absolute(argv[1]);
        require(fs::is_regular_file(script),"Slicer release builder is missing");
        Scratch temp;
        const auto source=temp.root/"source";
        write(source/"support/VERSION","0.0.4\n");
        write(source/"support/version.inc","# fixture\n");
        write(source/"CMakeLists.txt","# fixture\n");
        write(source/"keep-source","preserve\n");
        const auto binary=temp.root/"bin";
        const auto log=temp.root/"cmake-called";
        write(binary/"pkg-config","#!/bin/sh\nexit 0\n",true);
        write(binary/"cmake","#!/bin/sh\nprintf called >> \"$FIXTURE_LOG\"\nexit 42\n",true);
        const auto invoke=[&](const fs::path& root,bool clean){
            std::error_code error;
            fs::remove(log,error);
            return run(source,script,binary,log,root,clean);
        };
        require(invoke(source,true)!=0&&!fs::exists(log),
                "source checkout accepted as destructive release build root");
        require(read(source/"keep-source")=="preserve\n",
                "source checkout was modified by a rejected clean");
        const auto foreign=temp.root/"foreign";
        write(foreign/"unrelated","preserve\n");
        require(invoke(foreign,true)!=0&&!fs::exists(log),
                "foreign nonempty build root accepted for deletion");
        require(read(foreign/"unrelated")=="preserve\n",
                "unrelated foreign build root content was deleted");
        const auto owned=temp.root/"owned";
        require(invoke(owned,false)==42&&fs::exists(log),
                "new owned build root did not proceed to stubbed CMake");
        auto owner=read(owned/".slicer-release-owner");
        while(!owner.empty()&&(owner.back()=='\n'||owner.back()=='\r'))owner.pop_back();
        require(owner==fs::canonical(source).string(),
                "release build root ownership marker differs from checkout");
        write(owned/"stale","old build\n");
        require(invoke(owned,true)==42&&fs::exists(log),
                "owned clean did not proceed to stubbed CMake");
        require(!fs::exists(owned/"stale")&&
                fs::exists(source/"keep-source")&&fs::exists(foreign/"unrelated"),
                "owned clean removed foreign or source content");
        const auto legacy=temp.root/"legacy";
        write(legacy/"deps/CMakeCache.txt",
              "CMAKE_HOME_DIRECTORY:INTERNAL="+fs::canonical(source).string()+"/deps\n");
        require(invoke(legacy,false)==42&&fs::exists(log)&&
                fs::is_regular_file(legacy/".slicer-release-owner"),
                "legacy CMake cache owned by this source was not accepted");
        require(!fs::exists(source/"support/linux/verify-build-root.py"),
                "retired Python build-root verifier returned");
        std::cout<<"Release build-root ownership contracts passed (native C++17)\n";
        return 0;
    }catch(const std::exception& error){
        std::cerr<<"Slicer release build-root regression failed: "<<error.what()<<'\n';
        return 1;
    }
}
