// SPDX-License-Identifier: MIT
pragma solidity ^0.8.21;

// Local Imports
import { DebtService } from "src/services/DebtService.sol";
import { SwapService } from "src/services/SwapService.sol";
import { IERC20 } from "src/interfaces/token/IERC20.sol";

/// @title Position
/// @author Chain Rule, LLC
/// @notice Manages the owner's individual position
contract Position is DebtService, SwapService {
    // Immutables: no SLOAD to save gas
    address public immutable B_TOKEN;

    // Events
    event Short(uint256 cAmt, uint256 dAmt, uint256 bAmt);
    event Close(uint256 gains);

    constructor(address _owner, address _cToken, address _dToken, address _bToken)
        DebtService(_owner, _cToken, _dToken)
    {
        B_TOKEN = _bToken;
    }

    /**
     * @notice Adds to this contract's short position.
     * @param _cAmt The amount of collateral to be supplied for this transaction-specific loan (units: C_DECIMALS).
     * @param _ltv The desired loan-to-value ratio for this transaction-specific loan (ex: 75 is 75%).
     * @param _swapAmtOutMin The minimum amount of output tokens from swap for the tx to go through.
     * @param _poolFee The fee of the Uniswap pool.
     */
    function short(uint256 _cAmt, uint256 _ltv, uint256 _swapAmtOutMin, uint24 _poolFee) public payable onlyOwner {
        // 1. Transfer collateral to this contract
        IERC20(C_TOKEN).transferFrom(msg.sender, address(this), _cAmt);

        // 2. Borrow debt token
        uint256 dAmt = _borrow(_cAmt, _ltv);

        // 3. Swap debt token for base token
        (, uint256 bAmt) = _swapExactInput(D_TOKEN, B_TOKEN, dAmt, _swapAmtOutMin, _poolFee);

        // 4. Emit event
        emit Short(_cAmt, dAmt, bAmt);
    }

    /**
     * @notice Fully closes the short position.
     * @param _poolFee The fee of the Uniswap pool.
     * @param _exactOutput Whether to swap exact output or exact input (true for exact output, false for exact input).
     * @param _swapAmtOutMin The minimum amount of output tokens from swap for the tx to go through (only used if _exactOutput is false, supply 0 if true).
     * @param _withdrawBuffer The amount of collateral left as safety buffer for tx to go through (default = 100_000, units: 8 decimals).
     */
    function close(uint24 _poolFee, bool _exactOutput, uint256 _swapAmtOutMin, uint256 _withdrawBuffer)
        public
        payable
        onlyOwner
    {
        uint256 bTokenBalance = IERC20(B_TOKEN).balanceOf(address(this));

        // 1. Swap base token for debt token
        uint256 bAmtIn;
        uint256 dAmtOut;
        if (_exactOutput) {
            (bAmtIn, dAmtOut) = _swapExactOutput(B_TOKEN, D_TOKEN, _getDebtAmt(), bTokenBalance, _poolFee);
        } else {
            (bAmtIn, dAmtOut) = _swapExactInput(B_TOKEN, D_TOKEN, bTokenBalance, _swapAmtOutMin, _poolFee);
        }

        // 2. Repay debt token
        _repay(dAmtOut);

        // 3. Withdraw collateral to owner
        _withdraw(OWNER, _withdrawBuffer);

        // 4. Pay gains if any
        uint256 gains = bTokenBalance - bAmtIn;

        if (gains > 0) {
            IERC20(B_TOKEN).transfer(OWNER, gains);
        }

        // 5. Emit event
        emit Close(gains);
    }

    /**
     * @notice Increases the collateral amount for this contract's short position.
     * @param _cAmt The amount of collateral to be supplied for this contract's loan (units: C_DECIMALS).
     * @return ltv The loan-to-value ratio for this contract's loan (ex: 75 is 75%).
     */
    function addCollateral(uint256 _cAmt) public payable onlyOwner returns (uint256 ltv) {
        // 1. Transfer collateral from owner to this contract
        IERC20(C_TOKEN).transferFrom(msg.sender, address(this), _cAmt);

        // 2. Increase collateral for this contract's loan and return latest loan-to-value ratio
        ltv = _increaseCollateral(_cAmt);
    }
}
