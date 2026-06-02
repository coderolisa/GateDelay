// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

/// @notice Smart contract arithmetic library for fixed-point math.
library PRBMath {
    uint256 internal constant SCALE = 1e18;

    /// @notice Calculates floor(x*y÷denominator) with full precision.
    /// @dev Reverts if denominator == 0 or the calculation overflows uint256.
    function mulDiv(uint256 x, uint256 y, uint256 denominator) internal pure returns (uint256 result) {
        unchecked {
            uint256 prod0;
            uint256 prod1;
            assembly {
                let mm := mulmod(x, y, not(0))
                prod0 := mul(x, y)
                prod1 := sub(sub(mm, prod0), lt(mm, prod0))
            }

            if (prod1 == 0) {
                require(denominator > 0, "PRBMath: denominator zero");
                return prod0 / denominator;
            }

            require(denominator > prod1, "PRBMath: overflow");

            uint256 remainder;
            assembly {
                remainder := mulmod(x, y, denominator)
                prod1 := sub(prod1, gt(remainder, prod0))
                prod0 := sub(prod0, remainder)
            }

            uint256 twos = denominator & (~denominator + 1);
            assembly {
                denominator := div(denominator, twos)
                prod0 := div(prod0, twos)
                twos := add(div(sub(0, twos), twos), 1)
            }

            prod0 |= prod1 * twos;
            uint256 inverse = (3 * denominator) ^ 2;
            inverse *= 2 - denominator * inverse;
            inverse *= 2 - denominator * inverse;
            inverse *= 2 - denominator * inverse;
            inverse *= 2 - denominator * inverse;
            inverse *= 2 - denominator * inverse;
            inverse *= 2 - denominator * inverse;

            result = prod0 * inverse;
            return result;
        }
    }

    /// @notice Calculates floor(x*y÷SCALE) with full precision.
    function mulDivFixedPoint(uint256 x, uint256 y) internal pure returns (uint256 result) {
        result = mulDiv(x, y, SCALE);
    }
}
