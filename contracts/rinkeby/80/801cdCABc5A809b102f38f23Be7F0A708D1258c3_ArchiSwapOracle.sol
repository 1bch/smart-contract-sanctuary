// SPDX-License-Identifier: MIT
pragma solidity ^0.8.2;

interface IArchiSwapPair {
    function getReserves() external view returns (uint112 reserve0, uint112 reserve1, uint32 blockTimestampLast);
    function price0CumulativeLast() external view returns (uint);
    function price1CumulativeLast() external view returns (uint);
    function token0() external view returns (address);
    function token1() external view returns (address);
}

// sliding oracle that uses observations collected to provide moving price averages in the past
contract ArchiSwapOracle {

    address immutable public pair;
    Observation[65535] public observations;
    uint16 public length;
    // this is redundant with granularity and windowSize, but stored for gas savings & informational purposes.
    uint constant periodSize = 1800;
    uint Q112 = 2**112;
    uint e10 = 10**18;

    constructor(address _pair) {
        pair = _pair;
        (,,uint32 timestamp) = IArchiSwapPair(_pair).getReserves();
        uint112 _price0CumulativeLast = uint112(IArchiSwapPair(_pair).price0CumulativeLast() * e10 / Q112);
        uint112 _price1CumulativeLast = uint112(IArchiSwapPair(_pair).price1CumulativeLast() * e10 / Q112);
        observations[length++] = Observation(timestamp, _price0CumulativeLast, _price1CumulativeLast);
    }

    struct Observation {
        uint32 timestamp;
        uint112 price0Cumulative;
        uint112 price1Cumulative;
    }

    // Pre-cache slots for cheaper oracle writes
    function cache(uint size) external {
        uint _length = length+size;
        for (uint i = length; i < _length; i++) observations[i].timestamp = 1;
    }

    // update the current feed for free
    function update() external returns (bool) {
        return _update();
    }

    function updateable() external view returns (bool) {
        Observation memory _point = observations[length-1];
        (,, uint timestamp) = IArchiSwapPair(pair).getReserves();
        uint timeElapsed = timestamp - _point.timestamp;
        return timeElapsed > periodSize;
    }

    function _update() internal returns (bool) {
        Observation memory _point = observations[length-1];
        (,, uint32 timestamp) = IArchiSwapPair(pair).getReserves();
        uint32 timeElapsed = timestamp - _point.timestamp;
        if (timeElapsed > periodSize) {
            uint112 _price0CumulativeLast = uint112(IArchiSwapPair(pair).price0CumulativeLast() * e10 / Q112);
            uint112 _price1CumulativeLast = uint112(IArchiSwapPair(pair).price1CumulativeLast() * e10 / Q112);
            observations[length++] = Observation(timestamp, _price0CumulativeLast, _price1CumulativeLast);
            return true;
        }
        return false;
    }

    function _computeAmountOut(uint start, uint end, uint elapsed, uint amountIn) internal view returns (uint amountOut) {
        amountOut = amountIn * (end - start) / e10 / elapsed;
    }

    function current(address tokenIn, uint amountIn, address tokenOut) external view returns (uint amountOut, uint lastUpdatedAgo) {
        (address token0,) = tokenIn < tokenOut ? (tokenIn, tokenOut) : (tokenOut, tokenIn);

        Observation memory _observation = observations[length-1];
        uint price0Cumulative = IArchiSwapPair(pair).price0CumulativeLast() * e10 / Q112;
        uint price1Cumulative = IArchiSwapPair(pair).price1CumulativeLast() * e10 / Q112;
        (,,uint timestamp) = IArchiSwapPair(pair).getReserves();

        // Handle edge cases where we have no updates, will revert on first reading set
        if (timestamp == _observation.timestamp) {
            _observation = observations[length-2];
        }

        uint timeElapsed = timestamp - _observation.timestamp;
        timeElapsed = timeElapsed == 0 ? 1 : timeElapsed;
        if (token0 == tokenIn) {
            amountOut = _computeAmountOut(_observation.price0Cumulative, price0Cumulative, timeElapsed, amountIn);
        } else {
            amountOut = _computeAmountOut(_observation.price1Cumulative, price1Cumulative, timeElapsed, amountIn);
        }
        lastUpdatedAgo = timeElapsed;
    }

    function quote(address tokenIn, uint amountIn, address tokenOut, uint points) external view returns (uint amountOut, uint lastUpdatedAgo) {
        (address token0,) = tokenIn < tokenOut ? (tokenIn, tokenOut) : (tokenOut, tokenIn);

        uint priceAverageCumulative = 0;
        uint _length = length-1;
        uint i = _length - points;
        Observation memory currentObservation;
        Observation memory nextObservation;

        uint nextIndex = 0;
        if (token0 == tokenIn) {
            for (; i < _length; i++) {
                nextIndex = i+1;
                currentObservation = observations[i];
                nextObservation = observations[nextIndex];
                priceAverageCumulative += _computeAmountOut(
                    currentObservation.price0Cumulative,
                    nextObservation.price0Cumulative,
                    nextObservation.timestamp - currentObservation.timestamp, amountIn);
            }
        } else {
            for (; i < _length; i++) {
                nextIndex = i+1;
                currentObservation = observations[i];
                nextObservation = observations[nextIndex];
                priceAverageCumulative += _computeAmountOut(
                    currentObservation.price1Cumulative,
                    nextObservation.price1Cumulative,
                    nextObservation.timestamp - currentObservation.timestamp, amountIn);
            }
        }
        amountOut = priceAverageCumulative / points;

        (,,uint timestamp) = IArchiSwapPair(pair).getReserves();
        lastUpdatedAgo = timestamp - nextObservation.timestamp;
    }

    function sample(address tokenIn, uint amountIn, address tokenOut, uint points, uint window) external view returns (uint[] memory prices, uint lastUpdatedAgo) {
        (address token0,) = tokenIn < tokenOut ? (tokenIn, tokenOut) : (tokenOut, tokenIn);
        prices = new uint[](points);

        if (token0 == tokenIn) {
            {
                uint _length = length-1;
                uint i = _length - (points * window);
                uint _index = 0;
                Observation memory nextObservation;
                for (; i < _length; i+=window) {
                    Observation memory currentObservation;
                    currentObservation = observations[i];
                    nextObservation = observations[i + window];
                    prices[_index] = _computeAmountOut(
                        currentObservation.price0Cumulative,
                        nextObservation.price0Cumulative,
                        nextObservation.timestamp - currentObservation.timestamp, amountIn);
                    _index = _index + 1;
                }

                (,,uint timestamp) = IArchiSwapPair(pair).getReserves();
                lastUpdatedAgo = timestamp - nextObservation.timestamp;
            }
        } else {
            {
                uint _length = length-1;
                uint i = _length - (points * window);
                uint _index = 0;
                Observation memory nextObservation;
                for (; i < _length; i+=window) {
                    Observation memory currentObservation;
                    currentObservation = observations[i];
                    nextObservation = observations[i + window];
                    prices[_index] = _computeAmountOut(
                        currentObservation.price1Cumulative,
                        nextObservation.price1Cumulative,
                        nextObservation.timestamp - currentObservation.timestamp, amountIn);
                    _index = _index + 1;
                }

                (,,uint timestamp) = IArchiSwapPair(pair).getReserves();
                lastUpdatedAgo = timestamp - nextObservation.timestamp;
            }
        }
    }
}

{
  "evmVersion": "istanbul",
  "libraries": {},
  "metadata": {
    "bytecodeHash": "ipfs",
    "useLiteralContent": true
  },
  "optimizer": {
    "enabled": true,
    "runs": 200
  },
  "remappings": [],
  "outputSelection": {
    "*": {
      "*": [
        "evm.bytecode",
        "evm.deployedBytecode",
        "abi"
      ]
    }
  }
}