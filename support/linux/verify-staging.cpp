// SPDX-License-Identifier: AGPL-3.0-or-later
// Native C++17 regression of the actual production CMake install rules.
// Build and installation occur only inside a disposable private fixture.
#include <cerrno>
#include <cstdlib>
#include <filesystem>
#include <fstream>
#include <iostream>
#include <iterator>
#include <stdexcept>
#include <string>
#include <vector>
#include <sys/types.h>
#include <sys/wait.h>
#include <unistd.h>
namespace fs=std::filesystem;
static void check(bool ok,const std::string& reason) {
    if(!ok)throw std::runtime_error(reason);
}
static std::string read_file(const fs::path& path) {
    std::ifstream file(path,std::ios::binary);
    check(bool(file),"Cannot read "+path.string());
    return {std::istreambuf_iterator<char>(file),std::istreambuf_iterator<char>()};
}
static void write_file(const fs::path& path,const std::string& content) {
    fs::create_directories(path.parent_path());
    std::ofstream file(path,std::ios::binary|std::ios::trunc);
    check(bool(file),"Cannot create "+path.string());
    file<<content;
    file.close();
    check(bool(file),"Cannot write "+path.string());
}
static std::string trim(const std::string& value){
    const auto start=value.find_first_not_of(" \t\r\n");
    if(start==std::string::npos)return {};
    const auto last=value.find_last_not_of(" \t\r\n");
    return value.substr(start,last-start+1);
}
struct Scratch {
    fs::path dir;
    Scratch() {
        auto pattern=(fs::temp_directory_path()/"slicer-staging-XXXXXXXX").string();
        std::vector<char> name(pattern.begin(),pattern.end());
        name.push_back('\0');
        const char* made=mkdtemp(name.data());
        check(made!=nullptr,"Cannot allocate disposable CMake build root");
        dir=made;
    }
    ~Scratch(){std::error_code error;if(!dir.empty())fs::remove_all(dir,error);}
    Scratch(const Scratch&)=delete;
    Scratch& operator=(const Scratch&)=delete;
};
static std::string command(const std::vector<std::string>& parts,
                           const fs::path& stage={}) {
    check(!parts.empty(),"Empty CMake command");
    int pipes[2];
    check(pipe(pipes)==0,"Cannot allocate CMake command output");
    const pid_t pid=fork();
    if(pid<0){
        close(pipes[0]);close(pipes[1]);
        throw std::runtime_error("Cannot fork CMake test subprocess");
    }
    if(pid==0){
        close(pipes[0]);
        if(!stage.empty()&&setenv("DESTDIR",stage.c_str(),1)!=0)_exit(127);
        if(dup2(pipes[1],STDOUT_FILENO)<0||dup2(pipes[1],STDERR_FILENO)<0)
            _exit(127);
        close(pipes[1]);
        std::vector<char*> args;
        for(const auto& part:parts)args.push_back(const_cast<char*>(part.c_str()));
        args.push_back(nullptr);
        execvp(args[0],args.data());
        _exit(127);
    }
    close(pipes[1]);
    std::string output;
    char buffer[4096];
    while(true){
        const ssize_t count=::read(pipes[0],buffer,sizeof(buffer));
        if(count==0)break;
        if(count<0){
            if(errno==EINTR)continue;
            close(pipes[0]);
            throw std::runtime_error("Cannot capture CMake subprocess output");
        }
        check(output.size()+static_cast<std::size_t>(count)<2*1024*1024,
              "CMake staging subprocess emitted excessive output");
        output.append(buffer,static_cast<std::size_t>(count));
    }
    close(pipes[0]);
    int status=0;
    while(waitpid(pid,&status,0)<0){
        if(errno==EINTR)continue;
        throw std::runtime_error("Cannot wait for CMake staging subprocess");
    }
    check(WIFEXITED(status)&&WEXITSTATUS(status)==0,
          "Staging command failed ("+parts[0]+"):\n"+output);
    return output;
}
int main(int argc,char** argv) {
    try{
        check(argc<=2,"Usage: verify-staging [SOURCE_ROOT]");
        const auto root=fs::absolute(argc==2?fs::path(argv[1]):fs::path("."));
        const auto source=read_file(root/"CMakeLists.txt");
        const auto rules_source=read_file(root/"src/CMakeLists.txt");
        const auto builder=read_file(root/"support/linux/build-deb.sh");
        std::string minimum;
        for(std::size_t start=0;start<source.size();) {
            const auto end=source.find('\n',start);
            const auto line=trim(source.substr(start,end==std::string::npos?
                                                std::string::npos:end-start));
            if(line.rfind("cmake_minimum_required(",0)==0&&line.back()==')') {
                minimum=line;break;
            }
            if(end==std::string::npos)break;
            start=end+1;
        }
        check(!minimum.empty(),"Production CMake minimum policy missing");
        const auto target_rule=std::string("install(TARGETS PrusaSlicer RUNTIME DESTINATION \"")+
                               "$"+"{CMAKE_INSTALL_BINDIR}\")";
        std::vector<std::string> rules;
        for(std::size_t start=0;start<rules_source.size();) {
            const auto end=rules_source.find('\n',start);
            const auto line=trim(rules_source.substr(start,end==std::string::npos?
                                                     std::string::npos:end-start));
            if(line.find(target_rule)!=std::string::npos||
               (line.find("install(CODE ")!=std::string::npos&&
                line.find("create_symlink")!=std::string::npos))
                rules.push_back(line);
            if(end==std::string::npos)break;
            start=end+1;
        }
        check(rules.size()==3,"CMake fixture must mirror exactly three production install rules");
        const auto start=builder.find("cmake -S . -B \"$app_build\"");
        check(start!=std::string::npos,"Missing production app configure");
        const auto end=builder.find("cmake --build \"$app_build\"",start);
        check(end!=std::string::npos,"Missing production app build");
        check(builder.substr(start,end-start).find("-DCMAKE_POLICY_DEFAULT_CMP0087=NEW")!=
              std::string::npos,"Production CMake policy CMP0087 must be NEW");
        Scratch temp;
        for(const auto& mode:{"legacy","production"}){
            const bool modern=std::string(mode)=="production";
            const auto fixture=temp.dir/mode;
            fs::create_directories(fixture);
            std::string recipe=minimum+"\nproject(SlicerStagingRegression LANGUAGES C)\n"
                "include(GNUInstallDirs)\n"
                "add_executable(PrusaSlicer main.c)\n"
                "set_target_properties(PrusaSlicer PROPERTIES OUTPUT_NAME \"prusa-slicer\")\n";
            for(const auto& rule:rules)recipe+=rule+"\n";
            write_file(fixture/"CMakeLists.txt",recipe);
            write_file(fixture/"main.c",
                "#include <stdio.h>\nint main(void) { puts(\"Slicer staging regression\"); return 0; }\n");
            const auto build=fixture/"build";
            const auto stage=fixture/"stage";
            std::vector<std::string> configure={"cmake","-S",fixture.string(),"-B",
                                                  build.string(),"-DCMAKE_INSTALL_PREFIX=/usr"};
            if(modern)configure.emplace_back("-DCMAKE_POLICY_DEFAULT_CMP0087=NEW");
            command(configure);
            command({"cmake","--build",build.string()});
            command({"cmake","--install",build.string()},stage);
            for(const auto& name:{"slicer","prusa-gcodeviewer"}){
                const auto launch=stage/"usr/bin"/name;
                check(fs::is_symlink(launch),"Missing packaged launcher: "+launch.string());
                const auto actual=fs::read_symlink(launch).generic_string();
                if(!modern){
                    check(actual=="$<TARGET_FILE_NAME:PrusaSlicer>",
                        "Legacy policy no longer reproduces broken generator-expression link");
                    check(!fs::exists(launch),"Broken legacy symlink unexpectedly resolves");
                }else{
                    check(actual=="prusa-slicer","Release launcher must use relative target");
                    check(fs::exists(launch)&&access(launch.c_str(),X_OK)==0,
                        "Installed launcher must resolve to executable target");
                    check(trim(command({launch.string()}))=="Slicer staging regression",
                        "Installed launcher failed executable smoke test");
                }
            }
        }
        check(!fs::exists(root/"support/linux/verify-staging.py"),
              "Retired Python staging regression returned");
        std::cout<<"Slicer CMake launcher staging: PASS (legacy rejection and production symlinks)\n";
        return 0;
    }catch(const std::exception& error){
        std::cerr<<"Slicer native staging contract failed: "<<error.what()<<'\n';
        return 1;
    }
}
