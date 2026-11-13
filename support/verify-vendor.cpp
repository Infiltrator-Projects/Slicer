// SPDX-License-Identifier: AGPL-3.0-or-later
// Offline verification of pinned, multi-part vendor archives. This utility
// does not download, unpack or modify dependency archives.
#include <algorithm>
#include <array>
#include <cerrno>
#include <cctype>
#include <csignal>
#include <cstdint>
#include <filesystem>
#include <fstream>
#include <iostream>
#include <iterator>
#include <map>
#include <regex>
#include <set>
#include <stdexcept>
#include <string>
#include <utility>
#include <vector>
#include <sys/types.h>
#include <sys/wait.h>
#include <unistd.h>
namespace fs=std::filesystem;
static void require(bool ok,const std::string& why){
    if(!ok)throw std::runtime_error(why);
}
static std::string read(const fs::path& path){
    std::ifstream f(path,std::ios::binary);
    require(bool(f),"cannot read "+path.string());
    return {std::istreambuf_iterator<char>(f),std::istreambuf_iterator<char>()};
}
static std::map<std::string,std::string> manifest(const fs::path& path){
    const auto s=read(path);
    const std::regex assignment(R"ZZ(set\s*\(\s*([A-Za-z_][A-Za-z0-9_]*)\s+"([^"\\]*)"\s*\))ZZ");
    std::map<std::string,std::string> values;
    std::size_t pos=0;
    while(pos<s.size()){
        if(std::isspace(static_cast<unsigned char>(s[pos]))){++pos;continue;}
        if(s[pos]=='#'){
            const auto e=s.find('\n',pos);
            pos=e==std::string::npos?s.size():e+1;
            continue;
        }
        std::smatch match;
        const auto first=s.cbegin()+std::ptrdiff_t(pos);
        require(std::regex_search(first,s.cend(),match,assignment,
                                  std::regex_constants::match_continuous),
                "manifest line "+std::to_string(1+std::count(s.begin(),s.begin()+std::ptrdiff_t(pos),'\n'))+
                " must be literal quoted set assignment");
        const auto key=match[1].str();
        require(values.emplace(key,match[2].str()).second,"duplicate manifest variable: "+key);
        pos+=std::size_t(match.length());
    }
    return values;
}
static std::vector<std::string> split(const std::string& value){
    std::vector<std::string> output;
    std::size_t start=0;
    while(true){
        const auto end=value.find(';',start);
        output.push_back(value.substr(start,end==std::string::npos?std::string::npos:end-start));
        if(end==std::string::npos)break;
        start=end+1;
    }
    return output;
}
static fs::path safe_path(const fs::path& root,const std::string& item,const std::string& name){
    require(!item.empty()&&item.find('\\')==std::string::npos&&
            item.find('\0')==std::string::npos&&item[0]!='/'&&
            item.find(':')==std::string::npos,
            name+" has an invalid relative path");
    const auto joined=fs::weakly_canonical(root/item);
    const auto relative=joined.lexically_relative(root);
    require(!relative.empty()&&relative.native()!="."&&
            *relative.begin()!=".."&&!relative.is_absolute(),
            name+" escapes vendor directory: "+item);
    return joined;
}
static std::string checksum(const std::vector<fs::path>& files,std::uint64_t& total){
    int input[2]{},output[2]{};
    require(pipe(input)==0,"cannot create SHA-256 input stream");
    if(pipe(output)!=0){close(input[0]);close(input[1]);throw std::runtime_error("cannot capture SHA-256");}
    const pid_t pid=fork();
    if(pid<0){
        close(input[0]);close(input[1]);close(output[0]);close(output[1]);
        throw std::runtime_error("cannot launch SHA-256 tool");
    }
    if(pid==0){
        close(input[1]);close(output[0]);
        if(dup2(input[0],STDIN_FILENO)<0||dup2(output[1],STDOUT_FILENO)<0)_exit(127);
        close(input[0]);close(output[1]);
        execlp("sha256sum","sha256sum","-",static_cast<char*>(nullptr));
        _exit(127);
    }
    close(input[0]);close(output[1]);
    // Do not permit a missing checksum command to terminate the verifier via SIGPIPE.
    struct sigaction old{},ignore{};
    ignore.sa_handler=SIG_IGN;
    sigemptyset(&ignore.sa_mask);
    ignore.sa_flags=0;
    require(sigaction(SIGPIPE,&ignore,&old)==0,"cannot configure checksum pipe");
    bool failed=false;
    std::array<char,1024*1024> buffer{};
    for(const auto& path:files){
        std::ifstream file(path,std::ios::binary);
        if(!file){failed=true;break;}
        while(file){
            file.read(buffer.data(),std::streamsize(buffer.size()));
            const auto length=file.gcount();
            if(length<0){failed=true;break;}
            total+=std::uint64_t(length);
            std::size_t offset=0;
            while(offset<std::size_t(length)){
                const auto n=write(input[1],buffer.data()+offset,std::size_t(length)-offset);
                if(n<0&&errno==EINTR)continue;
                if(n<=0){failed=true;break;}
                offset+=std::size_t(n);
            }
            if(failed)break;
        }
        if(file.bad())failed=true;
        if(failed)break;
    }
    close(input[1]);
    sigaction(SIGPIPE,&old,nullptr);
    std::string result;
    std::array<char,256> small{};
    while(true){
        const auto n=::read(output[0],small.data(),small.size());
        if(n==0)break;
        if(n<0){if(errno==EINTR)continue;failed=true;break;}
        if(result.size()+std::size_t(n)>1024){failed=true;break;}
        result.append(small.data(),std::size_t(n));
    }
    close(output[0]);
    int status=0;
    while(waitpid(pid,&status,0)<0){
        if(errno==EINTR)continue;
        throw std::runtime_error("cannot reap SHA-256 process");
    }
    require(!failed&&WIFEXITED(status)&&WEXITSTATUS(status)==0,
            "could not verify concatenated vendor archive parts");
    require(result.size()>=66&&result[64]==' ',"invalid SHA-256 tool output");
    const auto digest=result.substr(0,64);
    require(std::regex_match(digest,std::regex("[0-9a-f]{64}")),
            "invalid SHA-256 digest output");
    return digest;
}
int main(int argc,char** argv){
    try{
        require(argc<=2,"Usage: verify-vendor [VENDOR_DIRECTORY]");
        const auto vendor=fs::canonical(argc==2?fs::path(argv[1]):
                                            fs::path("support/deps/vendor"));
        const auto variables=manifest(vendor/"manifest.cmake");
        const auto package_entry=variables.find("SLICER_VENDOR_PACKAGES");
        require(package_entry!=variables.end()&&!package_entry->second.empty(),
                "SLICER_VENDOR_PACKAGES must list nonempty package names");
        const auto packages=split(package_entry->second);
        const std::regex package_name("[A-Za-z0-9_]+");
        std::set<std::string> unique;
        std::set<std::string> used={"SLICER_VENDOR_PACKAGES"};
        std::uint64_t total=0;
        for(const auto& name:packages){
            require(std::regex_match(name,package_name)&&unique.insert(name).second,
                    "duplicate or invalid vendor package name: "+name);
            std::map<std::string,std::string> fields;
            for(const auto* label:{"FILE","SHA256","PARTS","URL"}){
                const std::string key="SLICER_VENDOR_"+name+"_"+label;
                used.insert(key);
                const auto found=variables.find(key);
                require(found!=variables.end()&&!found->second.empty(),
                        "missing or empty manifest variable: "+key);
                fields.emplace(label,found->second);
            }
            require(std::regex_match(fields.at("SHA256"),std::regex("[0-9a-fA-F]{64}")),
                    name+" has invalid SHA256");
            safe_path(vendor,fields.at("FILE"),name+" FILE");
            const auto part_names=split(fields.at("PARTS"));
            std::set<std::string> part_identity;
            std::set<fs::path> real_identity;
            std::vector<fs::path> parts;
            for(const auto& part:part_names){
                require(!part.empty()&&part_identity.insert(part).second,
                        name+" PARTS must contain unique nonempty paths");
                const auto path=safe_path(vendor,part,name+" PARTS");
                require(real_identity.insert(path).second,
                        name+" PARTS refers to same file more than once");
                require(fs::is_regular_file(path),
                        name+" missing archive part: "+part);
                parts.push_back(path);
            }
            const auto digest=checksum(parts,total);
            auto expected=fields.at("SHA256");
            std::transform(expected.begin(),expected.end(),expected.begin(),
                           [](unsigned char c){return char(std::tolower(c));});
            require(digest==expected,name+" SHA256 mismatch: expected "+expected+", got "+digest);
        }
        for(const auto& [key,value]:variables)
            require(used.count(key)!=0,"undeclared manifest variable: "+key);
        require(!fs::exists("support/verify-vendor.py"),
                "retired Python vendor verifier still present");
        std::cout<<"Verified "<<packages.size()<<" vendored dependency archives ("<<total<<" bytes).\n";
        return 0;
    }catch(const std::exception& error){
        std::cerr<<"Vendor verification failed: "<<error.what()<<'\n';
        return 1;
    }
}
