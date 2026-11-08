// SPDX-License-Identifier: AGPL-3.0-or-later
// Portable C++17 verification of packaged MB TrueType font inventory,
// embedded family names and exact SHA-256 hashes. No Python or font renderer.
#include <algorithm>
#include <array>
#include <cctype>
#include <cstdint>
#include <filesystem>
#include <fstream>
#include <iomanip>
#include <iostream>
#include <iterator>
#include <regex>
#include <set>
#include <sstream>
#include <stdexcept>
#include <string>
#include <vector>
namespace fs=std::filesystem;
using Bytes=std::vector<std::uint8_t>;
static void require(bool yes,const std::string& why){
    if(!yes)throw std::runtime_error(why);
}
static Bytes bytes(const fs::path& path){
    std::ifstream f(path,std::ios::binary);
    require(bool(f),"cannot read "+path.string());
    const std::vector<char> data{std::istreambuf_iterator<char>(f),std::istreambuf_iterator<char>()};
    require(f.eof()||bool(f),"error reading "+path.string());
    return Bytes(data.begin(),data.end());
}
static std::string text(const fs::path& path){
    const auto data=bytes(path);
    return std::string(data.begin(),data.end());
}
static std::string field(const std::string& json,const std::string& name){
    const auto key=json.find("\""+name+"\"");
    require(key!=std::string::npos,"manifest missing "+name);
    auto p=json.find(':',key+name.size()+2);
    require(p!=std::string::npos,"invalid manifest field "+name);
    while(++p<json.size()&&std::isspace(static_cast<unsigned char>(json[p]))) {}
    require(p<json.size()&&json[p]=='"',"manifest field is not a string: "+name);
    std::string result;
    for(++p;p<json.size();++p){
        const char c=json[p];
        if(c=='"')return result;
        if(c=='\\'){
            require(++p<json.size(),"truncated JSON string escape");
            const char e=json[p];
            if(e=='"'||e=='\\'||e=='/')result.push_back(e);
            else if(e=='n')result.push_back('\n');
            else if(e=='r')result.push_back('\r');
            else if(e=='t')result.push_back('\t');
            else throw std::runtime_error("unsupported JSON escape in font manifest");
        }else result.push_back(c);
    }
    throw std::runtime_error("unterminated JSON field "+name);
}
struct Font{std::string filename,family,digest;};
static std::vector<Font> manifest_fonts(const std::string& src){
    const auto key=src.find("\"fonts\"");
    require(key!=std::string::npos,"font manifest missing fonts list");
    auto pos=src.find('[',key);
    require(pos!=std::string::npos,"font list is not an array");
    std::vector<Font> result;
    while(++pos<src.size()){
        while(pos<src.size()&&(std::isspace(static_cast<unsigned char>(src[pos]))||src[pos]==','))++pos;
        require(pos<src.size(),"unterminated font array");
        if(src[pos]==']')break;
        require(src[pos]=='{',"non-object entry in font array");
        const auto start=pos;
        bool quoted=false,escape=false;
        unsigned depth=0;
        for(;pos<src.size();++pos){
            const char c=src[pos];
            if(quoted){
                if(escape)escape=false;
                else if(c=='\\')escape=true;
                else if(c=='"')quoted=false;
            }else if(c=='"')quoted=true;
            else if(c=='{')++depth;
            else if(c=='}'&&--depth==0){++pos;break;}
        }
        require(depth==0&&pos<=src.size(),"unterminated font object");
        const auto obj=src.substr(start,pos-start);
        const Font f{field(obj,"file"),field(obj,"family"),field(obj,"sha256")};
        require(!f.filename.empty()&&fs::path(f.filename).filename()==f.filename,
                "invalid font filename in manifest");
        require(std::regex_match(f.digest,std::regex("[0-9a-f]{64}")),
                "invalid font SHA-256 for "+f.filename);
        result.push_back(f);
        --pos;
    }
    require(result.size()==3,"expected three pinned MB font entries");
    return result;
}
static std::uint32_t rotr(std::uint32_t v,unsigned n){return(v>>n)|(v<<(32-n));}
static std::string sha256(const Bytes& raw){
    static constexpr std::array<std::uint32_t,64> K{{
        0x428a2f98,0x71374491,0xb5c0fbcf,0xe9b5dba5,0x3956c25b,0x59f111f1,0x923f82a4,0xab1c5ed5,
        0xd807aa98,0x12835b01,0x243185be,0x550c7dc3,0x72be5d74,0x80deb1fe,0x9bdc06a7,0xc19bf174,
        0xe49b69c1,0xefbe4786,0x0fc19dc6,0x240ca1cc,0x2de92c6f,0x4a7484aa,0x5cb0a9dc,0x76f988da,
        0x983e5152,0xa831c66d,0xb00327c8,0xbf597fc7,0xc6e00bf3,0xd5a79147,0x06ca6351,0x14292967,
        0x27b70a85,0x2e1b2138,0x4d2c6dfc,0x53380d13,0x650a7354,0x766a0abb,0x81c2c92e,0x92722c85,
        0xa2bfe8a1,0xa81a664b,0xc24b8b70,0xc76c51a3,0xd192e819,0xd6990624,0xf40e3585,0x106aa070,
        0x19a4c116,0x1e376c08,0x2748774c,0x34b0bcb5,0x391c0cb3,0x4ed8aa4a,0x5b9cca4f,0x682e6ff3,
        0x748f82ee,0x78a5636f,0x84c87814,0x8cc70208,0x90befffa,0xa4506ceb,0xbef9a3f7,0xc67178f2
    }};
    std::array<std::uint32_t,8> h{{
        0x6a09e667,0xbb67ae85,0x3c6ef372,0xa54ff53a,
        0x510e527f,0x9b05688c,0x1f83d9ab,0x5be0cd19
    }};
    require(raw.size()<(std::uint64_t(1)<<58),"font too large for SHA-256");
    Bytes padded=raw;
    padded.push_back(0x80);
    while(padded.size()%64!=56)padded.push_back(0);
    const auto bitlen=std::uint64_t(raw.size())*8;
    for(int i=7;i>=0;--i)padded.push_back(std::uint8_t(bitlen>>(8*i)));
    for(std::size_t offset=0;offset<padded.size();offset+=64){
        std::array<std::uint32_t,64> w{};
        for(std::size_t i=0;i<16;i++){
            const std::size_t p=offset+i*4;
            w[i]=(std::uint32_t(padded[p])<<24)|(std::uint32_t(padded[p+1])<<16)|
                 (std::uint32_t(padded[p+2])<<8)|padded[p+3];
        }
        for(std::size_t i=16;i<64;i++){
            const auto a=w[i-15],b=w[i-2];
            const auto s0=rotr(a,7)^rotr(a,18)^(a>>3);
            const auto s1=rotr(b,17)^rotr(b,19)^(b>>10);
            w[i]=w[i-16]+s0+w[i-7]+s1;
        }
        auto a=h[0],b=h[1],c=h[2],d=h[3],e=h[4],f=h[5],g=h[6],z=h[7];
        for(std::size_t i=0;i<64;i++){
            const auto s1=rotr(e,6)^rotr(e,11)^rotr(e,25);
            const auto choice=(e&f)^(~e&g);
            const auto t1=z+s1+choice+K[i]+w[i];
            const auto s0=rotr(a,2)^rotr(a,13)^rotr(a,22);
            const auto majority=(a&b)^(a&c)^(b&c);
            const auto t2=s0+majority;
            z=g;g=f;f=e;e=d+t1;d=c;c=b;b=a;a=t1+t2;
        }
        h[0]+=a;h[1]+=b;h[2]+=c;h[3]+=d;h[4]+=e;h[5]+=f;h[6]+=g;h[7]+=z;
    }
    std::ostringstream hex;
    for(auto v:h)hex<<std::hex<<std::setfill('0')<<std::setw(8)<<v;
    return hex.str();
}
static std::uint16_t be16(const Bytes& data,std::size_t p){
    require(p<data.size()&&data.size()-p>=2,"truncated SFNT name table");
    return std::uint16_t((std::uint16_t(data[p])<<8)|data[p+1]);
}
static std::uint32_t be32(const Bytes& data,std::size_t p){
    require(p<data.size()&&data.size()-p>=4,"truncated SFNT directory");
    return (std::uint32_t(data[p])<<24)|(std::uint32_t(data[p+1])<<16)|
           (std::uint32_t(data[p+2])<<8)|data[p+3];
}
static void utf8_append(std::string& out,std::uint32_t c){
    if(c<0x80)out.push_back(char(c));
    else if(c<0x800){out.push_back(char(0xc0|(c>>6)));out.push_back(char(0x80|(c&63)));}
    else if(c<0x10000){
        out.push_back(char(0xe0|(c>>12)));
        out.push_back(char(0x80|((c>>6)&63)));
        out.push_back(char(0x80|(c&63)));
    }else{
        out.push_back(char(0xf0|(c>>18)));
        out.push_back(char(0x80|((c>>12)&63)));
        out.push_back(char(0x80|((c>>6)&63)));
        out.push_back(char(0x80|(c&63)));
    }
}
static std::string decode_utf16be(const Bytes& data,std::size_t offset,std::size_t count){
    require(count%2==0&&offset<=data.size()&&count<=data.size()-offset,
            "malformed UTF-16 font family record");
    std::string out;
    for(std::size_t p=offset;p<offset+count;p+=2){
        std::uint32_t c=be16(data,p);
        if(c>=0xd800&&c<=0xdbff){
            require(p+4<=offset+count,"truncated UTF-16 surrogate pair");
            const auto low=be16(data,p+2);
            require(low>=0xdc00&&low<=0xdfff,"invalid UTF-16 surrogate");
            c=0x10000+((c-0xd800)<<10)+(low-0xdc00);
            p+=2;
        }else require(c<0xdc00||c>0xdfff,"orphaned UTF-16 low surrogate");
        utf8_append(out,c);
    }
    return out;
}
static std::set<std::string> families(const Bytes& data){
    require(data.size()>=12&&be32(data,0)==0x00010000,"Expected a native TrueType font");
    const std::size_t table_count=be16(data,4);
    require(table_count<2048&&12+table_count*16<=data.size(),"malformed SFNT directory");
    std::size_t offset=0,length=0;
    for(std::size_t i=0;i<table_count;i++){
        const auto p=12+i*16;
        if(be32(data,p)==0x6e616d65){offset=be32(data,p+8);length=be32(data,p+12);break;}
    }
    require(length>=6&&offset<=data.size()&&length<=data.size()-offset,
            "Missing or malformed font name table");
    const auto records=std::size_t(be16(data,offset+2));
    const auto base=std::size_t(be16(data,offset+4));
    require(6+records*12<=length&&base<=length,"Malformed font name record list");
    std::set<std::string> names;
    for(std::size_t i=0;i<records;i++){
        const auto r=offset+6+i*12;
        const auto platform=be16(data,r),name=be16(data,r+6);
        if((platform==0||platform==3)&&(name==1||name==16)){
            const std::size_t size=be16(data,r+8),start=be16(data,r+10);
            require(base+start<=length&&size<=length-base-start,"Font family outside name table");
            names.insert(decode_utf16be(data,offset+base+start,size));
        }
    }
    return names;
}
int main(int argc,char** argv){
    try{
        require(argc<=2,"Usage: verify-fonts [FONT_DIRECTORY]");
        const fs::path root=fs::current_path();
        const fs::path dir=argc==2?fs::path(argv[1]):root/"support/resources/fonts";
        const auto manifest=manifest_fonts(text(root/"support/resources/fonts/manifest.json"));
        std::set<std::string> expected,actual;
        for(const auto& f:manifest)require(expected.insert(f.filename).second,
                                           "Duplicate font in manifest: "+f.filename);
        require(fs::is_directory(dir),"Font directory missing: "+dir.string());
        for(const auto& entry:fs::directory_iterator(dir)){
            if(!entry.is_regular_file())continue;
            std::string ext=entry.path().extension().string();
            std::transform(ext.begin(),ext.end(),ext.begin(),
                           [](unsigned char c){return char(std::tolower(c));});
            if(ext==".ttf"||ext==".ttc"||ext==".otf"||ext==".woff"||ext==".woff2")
                actual.insert(entry.path().filename().string());
        }
        require(actual==expected,"Unexpected bundled font inventory");
        for(const auto& f:manifest){
            const auto data=bytes(dir/f.filename);
            require(sha256(data)==f.digest,"Font SHA-256 mismatch: "+f.filename);
            require(families(data).count(f.family)!=0,
                    "Font family mismatch: "+f.filename);
        }
        require(!fs::exists(root/"support/verify-fonts.py"),
                "retired Python font validator still present");
        std::cout<<"Verified all three bundled MB fonts: exact bytes and native font families.\n";
        return 0;
    }catch(const std::exception& e){
        std::cerr<<"Native Slicer font verification failed: "<<e.what()<<'\n';
        return 1;
    }
}
