// SPDX-License-Identifier: GPL-3.0-or-later
// Build a small reproducible, commit-pinned Slicer native downloader.
// Read the committed Git tree, never mutable working-tree source or caches.
#include <array>
#include <cerrno>
#include <cstring>
#include <filesystem>
#include <fstream>
#include <iostream>
#include <iterator>
#include <regex>
#include <stdexcept>
#include <string>
#include <vector>
#include <sys/types.h>
#include <sys/wait.h>
#include <unistd.h>
namespace fs=std::filesystem;
static void require(bool condition,const std::string& why){
    if(!condition)throw std::runtime_error(why);
}
static std::string trim(std::string text){
    const auto begin=text.find_first_not_of(" \t\r\n");
    return begin==std::string::npos?std::string():
        text.substr(begin,text.find_last_not_of(" \t\r\n")-begin+1);
}
static std::string git(const fs::path& repository,const std::vector<std::string>& args){
    int pipefd[2];
    require(pipe(pipefd)==0,"could not open Git capture pipe");
    const pid_t pid=fork();
    if(pid<0){close(pipefd[0]);close(pipefd[1]);throw std::runtime_error("Git subprocess fork failed");}
    if(pid==0){
        close(pipefd[0]);
        if(dup2(pipefd[1],STDOUT_FILENO)<0)_exit(127);
        close(pipefd[1]);
        std::vector<std::string> own={"git","-C",repository.string()};
        own.insert(own.end(),args.begin(),args.end());
        std::vector<char*> argv;
        for(auto& a:own)argv.push_back(a.data());
        argv.push_back(nullptr);
        execvp("git",argv.data());
        _exit(127);
    }
    close(pipefd[1]);
    std::string result;
    std::array<char,16384> bytes{};
    bool error=false;
    for(;;){
        const ssize_t count=read(pipefd[0],bytes.data(),bytes.size());
        if(count==0)break;
        if(count<0){if(errno==EINTR)continue;error=true;break;}
        if(result.size()+std::size_t(count)>2*1024*1024){
            error=true;break;
        }
        result.append(bytes.data(),std::size_t(count));
    }
    close(pipefd[0]);
    int status=0;
    while(waitpid(pid,&status,0)<0){
        if(errno==EINTR)continue;
        throw std::runtime_error("cannot reap Git subprocess");
    }
    require(!error&&WIFEXITED(status)&&WEXITSTATUS(status)==0,
            "Git source revision or committed payload unavailable in "+repository.string());
    return result;
}
static void replace_all(std::string& text,const std::string& marker,const std::string& value){
    require(text.find(marker)!=std::string::npos,
            "Bootstrap template lacks "+marker);
    std::size_t offset=0;
    while((offset=text.find(marker,offset))!=std::string::npos){
        text.replace(offset,marker.size(),value);
        offset+=value.size();
    }
}
static fs::path build(const fs::path& repository,const std::string& source,
                      const fs::path& output_dir){
    const auto root=fs::canonical(repository);
    const std::string sha=trim(git(root,{"rev-parse","--verify","--end-of-options",
                                      source+"^{commit}"}));
    require(std::regex_match(sha,std::regex("[0-9a-f]{40}")),
            "Git returned invalid release revision");
    const std::string version=trim(git(root,{"show",sha+":support/VERSION"}));
    require(std::regex_match(version,std::regex("[0-9]+\\.[0-9]+\\.[0-9]+")),
            "support/VERSION must contain a numeric semantic version");
    std::string template_text=git(root,{"show",sha+":support/native/bootstrap.sh.in"});
    replace_all(template_text,"@SLICER_VERSION@",version);
    replace_all(template_text,"@SOURCE_SHA@",sha);
    replace_all(template_text,"@SOURCE_URL@",
                "https://github.com/Infiltrator-Projects/Slicer/archive/"+sha+".tar.gz");
    require(!std::regex_search(template_text,std::regex("@[A-Z][A-Z0-9_]*@")),
            "Bootstrap template contains unresolved release value");
    const fs::path target_root=fs::absolute(output_dir).lexically_normal();
    fs::create_directories(target_root);
    const fs::path artifact=target_root/("slicer-"+version+"-native-installer.run");
    const fs::path staging=artifact.string()+".tmp";
    try{
        {
            std::ofstream file(staging,std::ios::binary|std::ios::trunc);
            require(bool(file),"cannot create native installer staging file");
            file.write(template_text.data(),std::streamsize(template_text.size()));
            file.flush();
            require(bool(file),"cannot write complete native installer");
        }
        fs::permissions(staging,fs::perms::owner_read|fs::perms::owner_write|
                        fs::perms::owner_exec|fs::perms::group_read|
                        fs::perms::group_exec|fs::perms::others_read|
                        fs::perms::others_exec,fs::perm_options::replace);
        fs::rename(staging,artifact);
    }catch(...){
        std::error_code error;
        fs::remove(staging,error);
        throw;
    }
    return artifact;
}
int main(int argc,char** argv){
    try{
        std::string source="HEAD";
        fs::path output_dir="dist",repository=".";
        for(int i=1;i<argc;i++){
            const std::string option=argv[i];
            require(i+1<argc,"Missing argument for "+option);
            if(option=="--source-ref")source=argv[++i];
            else if(option=="--output-dir")output_dir=argv[++i];
            else if(option=="--repository")repository=argv[++i];
            else throw std::runtime_error("Unknown native installer option: "+option);
        }
        const auto target=build(repository,source,output_dir);
        std::cout<<target.string()<<'\n';
        return 0;
    }catch(const std::exception& error){
        std::cerr<<"Slicer native installer builder: "<<error.what()<<'\n';
        return 1;
    }
}
