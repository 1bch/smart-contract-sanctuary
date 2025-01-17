// SPDX-License-Identifier: MIT
pragma solidity ^0.8.2;

contract RenderBitmapSVG {
    // SPDX-License-Identifier: GPL-3.0

    struct SVGCursor {
        uint8 x;
        uint8 y;
        string color1;
        string color2;
        string color3;
        string color4;
    }

    function pixel4(string[32] memory lookup, SVGCursor memory pos)
        internal
        pure
        returns (string memory)
    {
        return
            string(
                abi.encodePacked(
                    '<rect fill="',
                    pos.color1,
                    '" x="',
                    lookup[pos.x],
                    '" y="',
                    lookup[pos.y],
                    '" width="1.5" height="1.5" />',
                    '<rect fill="',
                    pos.color2,
                    '" x="',
                    lookup[pos.x + 1],
                    '" y="',
                    lookup[pos.y],
                    '" width="1.5" height="1.5" />',
                    string(
                        abi.encodePacked(
                            '<rect fill="',
                            pos.color3,
                            '" x="',
                            lookup[pos.x + 2],
                            '" y="',
                            lookup[pos.y],
                            '" width="1.5" height="1.5" />',
                            '<rect fill="',
                            pos.color4,
                            '" x="',
                            lookup[pos.x + 3],
                            '" y="',
                            lookup[pos.y],
                            '" width="1.5" height="1.5" />'
                        )
                    )
                )
            );
    }

    function tokenSvgDataOf(uint8[] memory data, string[16] memory palette)
        public
        pure
        returns (string memory)
    {
        string
            memory svgString = '<?xml version="1.0" encoding="UTF-8" standalone="no"?><svg xmlns="http://www.w3.org/2000/svg" version="1.1" viewBox="0 0 32 32">';

        // prettier-ignore
        string[32] memory lookup=["0","1","2","3","4","5","6","7","8","9","10","11","12","13","14","15","16","17","18","19","20","21","22","23","24","25","26","27","28","29","30","31"];

        SVGCursor memory pos;

        string[8] memory p;

        for (uint8 i = 0; i < 32; i += 1) {
            for (uint8 j = 0; j < 8; j += 1) {
                pos.color1 = palette[data[pos.y * 32 + (pos.x)]];
                pos.color2 = palette[data[pos.y * 32 + (pos.x + 1)]];
                pos.color3 = palette[data[pos.y * 32 + (pos.x + 2)]];
                pos.color4 = palette[data[pos.y * 32 + (pos.x + 3)]];
                p[j] = pixel4(lookup, pos);
                pos.x += 4;
            }

            // prettier-ignore
            svgString = string( abi.encodePacked(
                    svgString,
                    p[0], p[1], p[2], p[3], p[4], p[5], p[6], p[7]
                )
            );

            if (pos.x >= 32) {
                pos.x = 0;
                pos.y += 1;
            }
        }

        svgString = string(abi.encodePacked(svgString, "</svg>"));
        return svgString;
    }
}

{
  "optimizer": {
    "enabled": false,
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