// SPDX-License-Identifier: MIT

pragma solidity ^0.8.2;

/// @author jpegmint.xyz

library JustBackgroundsColors {

    /**
     * @dev Compact colorBytes storage.
     * R G B N F T
     * 00ffff00790c
     * R = Red
     * G = Green
     * B = Blue
     * N = Name
     * F = Family
     * T = Source, Brightness, Special
     */
    function getColorMetadata(bytes1 bits) external pure returns (bytes6 colorBytes) {
        
             if (bits == 0x00) colorBytes = 0xf1f7fb5c0017;
        else if (bits == 0x01) colorBytes = 0xecc5c0c9054B;
        else if (bits == 0x02) colorBytes = 0x6c3f19fa0183;
        else if (bits == 0x03) colorBytes = 0x4169e1cd0002;
        else if (bits == 0x04) colorBytes = 0x708090e10202;
        else if (bits == 0x05) colorBytes = 0xfffacd870906;
        else if (bits == 0x06) colorBytes = 0xdecade52065B;
        else if (bits == 0x07) colorBytes = 0xa55e75100123;
        else if (bits == 0x08) colorBytes = 0xd10de55f0623;
        else if (bits == 0x09) colorBytes = 0xf1e57a6e092B;
        else if (bits == 0x0a) colorBytes = 0x00ffff0c0079;
        else if (bits == 0x0b) colorBytes = 0x000000200201;
        else if (bits == 0x0c) colorBytes = 0x0000ff220001;
        else if (bits == 0x0d) colorBytes = 0xff00ff750671;
        else if (bits == 0x0e) colorBytes = 0x8080807a0201;
        else if (bits == 0x0f) colorBytes = 0x0080007b0301;
        else if (bits == 0x10) colorBytes = 0x00ff00950301;
        else if (bits == 0x11) colorBytes = 0x8000009b0101;
        else if (bits == 0x12) colorBytes = 0x000080aa0001;
        else if (bits == 0x13) colorBytes = 0x808000af0301;
        else if (bits == 0x14) colorBytes = 0x800080c30601;
        else if (bits == 0x15) colorBytes = 0xff0000c70701;
        else if (bits == 0x16) colorBytes = 0xc0c0c0de0249;
        else if (bits == 0x17) colorBytes = 0x008080eb0301;
        else if (bits == 0x18) colorBytes = 0xfffffffc0805;
        else if (bits == 0x19) colorBytes = 0xffff00fe0909;
        else if (bits == 0x1a) colorBytes = 0x7fffd40d001A;
        else if (bits == 0x1b) colorBytes = 0x5f9ea02f0002;
        else if (bits == 0x1c) colorBytes = 0x6495ed3a0002;
        else if (bits == 0x1d) colorBytes = 0x00ffff3d007A;
        else if (bits == 0x1e) colorBytes = 0x00008b400002;
        else if (bits == 0x1f) colorBytes = 0x00ced14f0002;
        else if (bits == 0x20) colorBytes = 0x00bfff560002;
        else if (bits == 0x21) colorBytes = 0x1e90ff610002;
        else if (bits == 0x22) colorBytes = 0xadd8e688000A;
        else if (bits == 0x23) colorBytes = 0xe0ffff8a0006;
        else if (bits == 0x24) colorBytes = 0x87cefa91000A;
        else if (bits == 0x25) colorBytes = 0xb0c4de93000A;
        else if (bits == 0x26) colorBytes = 0x0000cd9d0002;
        else if (bits == 0x27) colorBytes = 0x48d1cca30002;
        else if (bits == 0x28) colorBytes = 0x191970a50002;
        else if (bits == 0x29) colorBytes = 0xafeeeeb6000A;
        else if (bits == 0x2a) colorBytes = 0xb0e0e6c2000A;
        else if (bits == 0x2b) colorBytes = 0x87ceebdf000A;
        else if (bits == 0x2c) colorBytes = 0x4682b4e60002;
        else if (bits == 0x2d) colorBytes = 0x40e0d0f8001A;
        else if (bits == 0x2e) colorBytes = 0xffe4c41f0106;
        else if (bits == 0x2f) colorBytes = 0xffebcd210106;
        else if (bits == 0x30) colorBytes = 0xa52a2a2c0102;
        else if (bits == 0x31) colorBytes = 0xdeb8872d018A;
        else if (bits == 0x32) colorBytes = 0xd2691e340102;
        else if (bits == 0x33) colorBytes = 0xfff8dc3b0106;
        else if (bits == 0x34) colorBytes = 0xb8860b420102;
        else if (bits == 0x35) colorBytes = 0xdaa520790102;
        else if (bits == 0x36) colorBytes = 0xffdeada9010A;
        else if (bits == 0x37) colorBytes = 0xcd853fbd0102;
        else if (bits == 0x38) colorBytes = 0xbc8f8fcc0102;
        else if (bits == 0x39) colorBytes = 0x8b4513cf0102;
        else if (bits == 0x3a) colorBytes = 0xf4a460d3010A;
        else if (bits == 0x3b) colorBytes = 0xa0522ddc0102;
        else if (bits == 0x3c) colorBytes = 0xd2b48ce9010A;
        else if (bits == 0x3d) colorBytes = 0xf5deb3fb010A;
        else if (bits == 0x3e) colorBytes = 0xa9a9a943020A;
        else if (bits == 0x3f) colorBytes = 0x2f4f4f4e0202;
        else if (bits == 0x40) colorBytes = 0x6969695e0202;
        else if (bits == 0x41) colorBytes = 0xdcdcdc76020A;
        else if (bits == 0x42) colorBytes = 0xd3d3d38c020A;
        else if (bits == 0x43) colorBytes = 0x778899920202;
        else if (bits == 0x44) colorBytes = 0x7fff0032030A;
        else if (bits == 0x45) colorBytes = 0x008b8b410302;
        else if (bits == 0x46) colorBytes = 0x006400440302;
        else if (bits == 0x47) colorBytes = 0x556b2f470302;
        else if (bits == 0x48) colorBytes = 0x8fbc8f4c030A;
        else if (bits == 0x49) colorBytes = 0x228b22740302;
        else if (bits == 0x4a) colorBytes = 0xadff2f7c030A;
        else if (bits == 0x4b) colorBytes = 0x7cfc0086030A;
        else if (bits == 0x4c) colorBytes = 0x90ee908d030A;
        else if (bits == 0x4d) colorBytes = 0x20b2aa900302;
        else if (bits == 0x4e) colorBytes = 0x32cd32960302;
        else if (bits == 0x4f) colorBytes = 0x66cdaa9c031A;
        else if (bits == 0x50) colorBytes = 0x3cb371a00302;
        else if (bits == 0x51) colorBytes = 0x00fa9aa20302;
        else if (bits == 0x52) colorBytes = 0x6b8e23b00302;
        else if (bits == 0x53) colorBytes = 0x98fb98b5030A;
        else if (bits == 0x54) colorBytes = 0x2e8b57d70302;
        else if (bits == 0x55) colorBytes = 0x00ff7fe40302;
        else if (bits == 0x56) colorBytes = 0x9acd32ff030A;
        else if (bits == 0x57) colorBytes = 0xffd70078094A;
        else if (bits == 0x58) colorBytes = 0xff7f50390402;
        else if (bits == 0x59) colorBytes = 0xff8c00480402;
        else if (bits == 0x5a) colorBytes = 0xff4500b20402;
        else if (bits == 0x5b) colorBytes = 0xff6347f40402;
        else if (bits == 0x5c) colorBytes = 0xff1493550502;
        else if (bits == 0x5d) colorBytes = 0xff69b47e0502;
        else if (bits == 0x5e) colorBytes = 0xffb6c18e050A;
        else if (bits == 0x5f) colorBytes = 0xc71585a40502;
        else if (bits == 0x60) colorBytes = 0xdb7093b70502;
        else if (bits == 0x61) colorBytes = 0xffc0cbbf050A;
        else if (bits == 0x62) colorBytes = 0x8a2be2230602;
        else if (bits == 0x63) colorBytes = 0x8b008b460602;
        else if (bits == 0x64) colorBytes = 0x9932cc490602;
        else if (bits == 0x65) colorBytes = 0x483d8b4d0602;
        else if (bits == 0x66) colorBytes = 0x9400d3500602;
        else if (bits == 0x67) colorBytes = 0x4b0082800602;
        else if (bits == 0x68) colorBytes = 0xe6e6fa840606;
        else if (bits == 0x69) colorBytes = 0xff00ff980672;
        else if (bits == 0x6a) colorBytes = 0xba55d39e0602;
        else if (bits == 0x6b) colorBytes = 0x9370db9f0602;
        else if (bits == 0x6c) colorBytes = 0x7b68eea10602;
        else if (bits == 0x6d) colorBytes = 0xda70d6b30602;
        else if (bits == 0x6e) colorBytes = 0xdda0ddc1060A;
        else if (bits == 0x6f) colorBytes = 0x6a5acde00602;
        else if (bits == 0x70) colorBytes = 0xd8bfd8ef060A;
        else if (bits == 0x71) colorBytes = 0xee82eef9060A;
        else if (bits == 0x72) colorBytes = 0xdc143c3c0702;
        else if (bits == 0x73) colorBytes = 0x8b00004a0702;
        else if (bits == 0x74) colorBytes = 0xe9967a4b070A;
        else if (bits == 0x75) colorBytes = 0xb22222700702;
        else if (bits == 0x76) colorBytes = 0xcd5c5c7f0702;
        else if (bits == 0x77) colorBytes = 0xf08080890702;
        else if (bits == 0x78) colorBytes = 0xffa07a8f070A;
        else if (bits == 0x79) colorBytes = 0xfa8072d20702;
        else if (bits == 0x7a) colorBytes = 0xf0f8ff080806;
        else if (bits == 0x7b) colorBytes = 0xfaebd70b0806;
        else if (bits == 0x7c) colorBytes = 0xf0ffff140806;
        else if (bits == 0x7d) colorBytes = 0xf5f5dc1c0806;
        else if (bits == 0x7e) colorBytes = 0xfffaf0720806;
        else if (bits == 0x7f) colorBytes = 0xf8f8ff770806;
        else if (bits == 0x80) colorBytes = 0xf0fff07d0806;
        else if (bits == 0x81) colorBytes = 0xfffff0810806;
        else if (bits == 0x82) colorBytes = 0xfff0f5850806;
        else if (bits == 0x83) colorBytes = 0xfaf0e6970806;
        else if (bits == 0x84) colorBytes = 0xf5fffaa60806;
        else if (bits == 0x85) colorBytes = 0xffe4e1a70806;
        else if (bits == 0x86) colorBytes = 0xfdf5e6ae0806;
        else if (bits == 0x87) colorBytes = 0xfff5eed80806;
        else if (bits == 0x88) colorBytes = 0xfffafae20806;
        else if (bits == 0x89) colorBytes = 0xf5f5f5fd0806;
        else if (bits == 0x8a) colorBytes = 0xbdb76b45090A;
        else if (bits == 0x8b) colorBytes = 0xf0e68c83090A;
        else if (bits == 0x8c) colorBytes = 0xfafad28b0906;
        else if (bits == 0x8d) colorBytes = 0xffffe0940906;
        else if (bits == 0x8e) colorBytes = 0xffe4b5a80906;
        else if (bits == 0x8f) colorBytes = 0xeee8aab4090A;
        else if (bits == 0x90) colorBytes = 0xffefd5b90906;
        else if (bits == 0x91) colorBytes = 0xffdab9bb090A;
        else if (bits == 0x92) colorBytes = 0xffa500b10408;
        else if (bits == 0x93) colorBytes = 0x663399c60600;
        else if (bits == 0x94) colorBytes = 0xaccede01005B;
        else if (bits == 0x95) colorBytes = 0xbaffed160057;
        else if (bits == 0x96) colorBytes = 0xbedded1a005B;
        else if (bits == 0x97) colorBytes = 0xbeefed1b005B;
        else if (bits == 0x98) colorBytes = 0xdaffed3f0057;
        else if (bits == 0x99) colorBytes = 0xdeeded540257;
        else if (bits == 0x9a) colorBytes = 0xdeface570357;
        else if (bits == 0x9b) colorBytes = 0xdabbed3e065B;
        else if (bits == 0x9c) colorBytes = 0xfacade69055B;
        else if (bits == 0x9d) colorBytes = 0xbeaded18065B;
        else if (bits == 0x9e) colorBytes = 0xefface650957;
        else if (bits == 0x9f) colorBytes = 0x0de55aac0323;
        else if (bits == 0xa0) colorBytes = 0x0ff1cead002B;
        else if (bits == 0xa1) colorBytes = 0x50bbede30023;
        else if (bits == 0xa2) colorBytes = 0x51e57add032B;
        else if (bits == 0xa3) colorBytes = 0x57a71ce50323;
        else if (bits == 0xa4) colorBytes = 0x5ad157d00323;
        else if (bits == 0xa5) colorBytes = 0x5afe57d1032B;
        else if (bits == 0xa6) colorBytes = 0x5a55edd50023;
        else if (bits == 0xa7) colorBytes = 0x5c0ff5d60023;
        else if (bits == 0xa8) colorBytes = 0x5eabedd90023;
        else if (bits == 0xa9) colorBytes = 0x5ecededa002B;
        else if (bits == 0xaa) colorBytes = 0x5eededdb002B;
        else if (bits == 0xab) colorBytes = 0x70a575f20323;
        else if (bits == 0xac) colorBytes = 0x70ffeef3002B;
        else if (bits == 0xad) colorBytes = 0x7007edf50623;
        else if (bits == 0xae) colorBytes = 0x71c7acf0002B;
        else if (bits == 0xaf) colorBytes = 0x71db17f10323;
        else if (bits == 0xb0) colorBytes = 0x7abbede7002B;
        else if (bits == 0xb1) colorBytes = 0x7ac71ce80323;
        else if (bits == 0xb2) colorBytes = 0x7ea5edec0023;
        else if (bits == 0xb3) colorBytes = 0x7ea5e5ed0023;
        else if (bits == 0xb4) colorBytes = 0x7e57edee0623;
        else if (bits == 0xb5) colorBytes = 0xa55e550f0123;
        else if (bits == 0xb6) colorBytes = 0xa55157110123;
        else if (bits == 0xb7) colorBytes = 0xa77e57120123;
        else if (bits == 0xb8) colorBytes = 0xa771c5130623;
        else if (bits == 0xb9) colorBytes = 0xacac1a000923;
        else if (bits == 0xba) colorBytes = 0xacce5502032B;
        else if (bits == 0xbb) colorBytes = 0xace71c03032B;
        else if (bits == 0xbc) colorBytes = 0xac1d1c040723;
        else if (bits == 0xbd) colorBytes = 0xadd1c705002B;
        else if (bits == 0xbe) colorBytes = 0xad0be5060623;
        else if (bits == 0xbf) colorBytes = 0xaffec707032B;
        else if (bits == 0xc0) colorBytes = 0xb0a575240123;
        else if (bits == 0xc1) colorBytes = 0xb0bbed25062B;
        else if (bits == 0xc2) colorBytes = 0xb0bca726022B;
        else if (bits == 0xc3) colorBytes = 0xb0d1e527002B;
        else if (bits == 0xc4) colorBytes = 0xb00b1e280723;
        else if (bits == 0xc5) colorBytes = 0xb055e5290623;
        else if (bits == 0xc6) colorBytes = 0xb1de751d032B;
        else if (bits == 0xc7) colorBytes = 0xbab1e515062B;
        else if (bits == 0xc8) colorBytes = 0xba51c5170623;
        else if (bits == 0xc9) colorBytes = 0xbea575190923;
        else if (bits == 0xca) colorBytes = 0xc0ffee360027;
        else if (bits == 0xcb) colorBytes = 0xc0071e370723;
        else if (bits == 0xcc) colorBytes = 0xc1cada35022B;
        else if (bits == 0xcd) colorBytes = 0xcadd1e2e092B;
        else if (bits == 0xce) colorBytes = 0xcea5ed30062B;
        else if (bits == 0xcf) colorBytes = 0xd00dad620623;
        else if (bits == 0xd0) colorBytes = 0xd077ed630623;
        else if (bits == 0xd1) colorBytes = 0xd1bbed5d062B;
        else if (bits == 0xd2) colorBytes = 0xd155ed600623;
        else if (bits == 0xd3) colorBytes = 0xdeba5e51092B;
        else if (bits == 0xd4) colorBytes = 0xdec1de53052B;
        else if (bits == 0xd5) colorBytes = 0xdefea7580327;
        else if (bits == 0xd6) colorBytes = 0xdefec7590327;
        else if (bits == 0xd7) colorBytes = 0xde7ec75a0523;
        else if (bits == 0xd8) colorBytes = 0xde7e575b0423;
        else if (bits == 0xd9) colorBytes = 0xe57a7e680423;
        else if (bits == 0xda) colorBytes = 0xedd1e564052B;
        else if (bits == 0xdb) colorBytes = 0xeffec7660327;
        else if (bits == 0xdc) colorBytes = 0xf007ed730523;
        else if (bits == 0xdd) colorBytes = 0xf1bbed6d052B;
        else if (bits == 0xde) colorBytes = 0xf177ed710523;
        else if (bits == 0xdf) colorBytes = 0xface756a042B;
        else if (bits == 0xe0) colorBytes = 0xfa5c1a6b0723;
        else if (bits == 0xe1) colorBytes = 0xfa57ed6c0523;
        else if (bits == 0xe2) colorBytes = 0xe5e4e2c0054B;
        else if (bits == 0xe3) colorBytes = 0xb87333380143;
        else if (bits == 0xe4) colorBytes = 0x5a9487ba0343;
        else if (bits == 0xe5) colorBytes = 0xb5a6422a0943;
        else if (bits == 0xe6) colorBytes = 0xcd7f322b0443;
        else if (bits == 0xe7) colorBytes = 0xc1c1bbb8024B;
        else if (bits == 0xe8) colorBytes = 0x50c878670313;
        else if (bits == 0xe9) colorBytes = 0x6c2dc70a0613;
        else if (bits == 0xea) colorBytes = 0x5efb6e82031B;
        else if (bits == 0xeb) colorBytes = 0xfdeef4bc0817;
        else if (bits == 0xec) colorBytes = 0x2554c7d40013;
        else if (bits == 0xed) colorBytes = 0xf62217ce0713;
        else if (bits == 0xee) colorBytes = 0xfaf7f7c50817;
        else if (bits == 0xef) colorBytes = 0xeed1e3ca051B;
        else if (bits == 0xf0) colorBytes = 0xffc20009091B;
        else if (bits == 0xf1) colorBytes = 0xaa915fc40113;
        else if (bits == 0xf2) colorBytes = 0xf8dfa11e098B;
        else if (bits == 0xf3) colorBytes = 0xab9f8d0e0183;
        else if (bits == 0xf4) colorBytes = 0xdeb887ea098B;
        else if (bits == 0xf5) colorBytes = 0x4e312e330183;
        else if (bits == 0xf6) colorBytes = 0xc04000990783;
        else if (bits == 0xf7) colorBytes = 0x824526310183;
        else if (bits == 0xf8) colorBytes = 0xf6d7af6f098B;
        else if (bits == 0xf9) colorBytes = 0xedcaa1be098B;
        else if (bits == 0xfa) colorBytes = 0xa55b53c80183;
        else if (bits == 0xfb) colorBytes = 0x65000ccb0183;
        else if (bits == 0xfc) colorBytes = 0xf1c38e9a018B;
        else if (bits == 0xfd) colorBytes = 0xab8251ab0183;
        else if (bits == 0xfe) colorBytes = 0xfffffff60867;
        else if (bits == 0xff) colorBytes = 0xfffffff70837;

        return colorBytes;
    }
}

{
  "optimizer": {
    "enabled": true,
    "runs": 200
  },
  "outputSelection": {
    "*": {
      "*": [
        "evm.bytecode",
        "evm.deployedBytecode",
        "abi"
      ]
    }
  },
  "libraries": {}
}