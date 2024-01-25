// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { ERC20Burnable } from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Burnable.sol";
import { ERC20Permit } from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Permit.sol";
import { ERC20Votes } from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Votes.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { SafeMath } from "@openzeppelin/contracts/utils/math/SafeMath.sol";
import { AccessControl } from "@openzeppelin/contracts/access/AccessControl.sol";
import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";
import { IUniswapV2Factory } from "@uniswap/v2-core/contracts/interfaces/IUniswapV2Factory.sol";
import { IUniswapV2Router02 } from "@uniswap/v2-periphery/contracts/interfaces/IUniswapV2Router02.sol";

contract EvcToken is ERC20, AccessControl, ERC20Burnable, Ownable, ERC20Permit, ERC20Votes {

    using SafeERC20 for IERC20;
    using SafeMath for uint256;

    bytes32 public constant ADMIN_ROLE = keccak256("ADMIN_ROLE");
    bytes32 public constant OPERATOR_ROLE = keccak256("OPERATOR_ROLE");

    bool enableBuy = true;

    address public devAddr = 0x1856Cf49B13f3F7EAf3994fD1102347B50222902;
    address public nullAddr = 0x000000000000000000000000000000000000dEaD;
    address public USDC = 0x56c5fB8B886DE7166e8C7AA1c925Cf75ce305Da8;

    uint256 public deadBalance;
    uint256 public feeToDev = 5;
    uint256 public feeToNull = 90;
    uint256 public transferFee;

    mapping(address => bool) private _isExcludedFromFees;
    mapping(address => bool) public _isGetFees;

    event ExcludeFromFees(address indexed account, bool isExcluded);
    event GetFee(address indexed account, bool isGetFee);

    modifier onlyAdmin() {
        require(hasRole(ADMIN_ROLE, msg.sender), "Not authorized, only admin");
        _;
    }

    modifier onlyOperator() {
        require(hasRole(OPERATOR_ROLE, msg.sender), "Not authorized, only operator");
        _;
    }

    constructor() ERC20("EVCToken", "EVC") ERC20Permit("EVCToken") {
        _setupRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _setupRole(ADMIN_ROLE, msg.sender);
        _setupRole(OPERATOR_ROLE, msg.sender);
        IUniswapV2Router02 _quickSwapRouter = IUniswapV2Router02(0x8954AfA98594b838bda56FE4C12a09D7739D179b);
        address _quickSwapPair = IUniswapV2Factory(_quickSwapRouter.factory()).createPair(address(this), USDC);
        _isGetFees[_quickSwapPair] = true;
        _mint(msg.sender, 21000000 * (10 ** 18));
    }

    //View
    function circulatingSupply() public view returns(uint) {
        return super.totalSupply() - super.balanceOf(0x000000000000000000000000000000000000dEaD);
    }

    function isExcludedFromFees(address account) public view returns(bool) {
        return _isExcludedFromFees[account];
    }

    receive() external payable {}

    // The following functions are overrides required by Solidity.
    //Internal
    function _afterTokenTransfer(address from, address to, uint256 amount) internal override(ERC20, ERC20Votes) {
        // super._afterTokenTransfer(from, to, amount);
        // if (from != address(0) && to != address(0)) {
        //     _burn(to, (amount * transferFee) / 10 ** 4);
        // }
    }

    function _burn(address account, uint256 amount) internal override(ERC20, ERC20Votes) {
        super._burn(account, amount);
    }

    function _mint(address to, uint256 amount) internal override(ERC20, ERC20Votes) {
        super._mint(to, amount);
    }

    function _transfer(address from, address to, uint256 amount) internal override {
        require(from != address(0), "BEP20: transfer from the zero address");
        require(to != address(0), "BEP20: transfer to the zero address");
        if (amount == 0) {
            super._transfer(from, to, 0); //commenting
            return;
        }
        // indicates if fee should be deducted from transfer
        bool takeFee = true;
        // if any account belongs to _isExcludedFromFee account then remove the fee
        if (_isExcludedFromFees[from] || _isExcludedFromFees[to]) {
            takeFee = false;
        }
        if (takeFee) {
            uint256 feesToNull;
            uint256 feesToDev;
            if (_isGetFees[from] || _isGetFees[to]) {
                if (_isGetFees[from]) {
                    require((enableBuy == true), "Buy is not enabled");
                    super._transfer(from, address(this), 0); //commenting
                } else {
                    // fees = amount.mul(totalFeesOnSell).div(10 ** 2);
                    // super._transfer(from, address(this), fees);
                    address nullAddress = nullAddr;
                    address devAddress = devAddr;
                    feesToNull = amount.mul(feeToNull).div(10 ** 2);
                    feesToDev = amount.mul(feeToDev).div(10 ** 2);
                    super._transfer(from, nullAddress, feesToNull);
                    super._transfer(from, devAddress, feesToDev);
                }
                uint256 totalFees = feesToNull + feesToDev;
                amount = amount.sub(totalFees);
            }
        }
        super._transfer(from, to, amount);
    }

    //Admin
    function mint(address to, uint256 amount) public onlyOwner {
        uint256 totalSupplyLimit = 2100000 * 10 ** 18;
        if (super.totalSupply() >= totalSupplyLimit) {
            require(amount <= deadBalance, "Tokenomics limit exceeded");
            deadBalance -= amount;
        }
        _mint(to, amount);
    }

    function updateDeadBalance(uint amount) external {
        deadBalance += amount;
    }


    function excludeFromFees(address account, bool excluded) public onlyAdmin {
        _isExcludedFromFees[account] = excluded;
        emit ExcludeFromFees(account, excluded);
    }

    function grantAdminRole(address account) public onlyAdmin {
        grantRole(ADMIN_ROLE, account);
    }

    function grantOperatorRole(address account) public onlyAdmin {
        grantRole(OPERATOR_ROLE, account);
    }

    function revokeAdminRole(address account) public onlyAdmin {
        revokeRole(ADMIN_ROLE, account);
    }

    function revokeOperatorRole(address account) public onlyAdmin {
        revokeRole(OPERATOR_ROLE, account);
    }

    function setEnableBuy(bool _enableBuy) public onlyAdmin {
        enableBuy = _enableBuy;
    }

    function setFeeAccount(address account, bool isGetFee) public onlyOperator {
        require(_isGetFees[account] != isGetFee, "Account is already the value of 'isGetFee'");
        _isGetFees[account] = isGetFee;
        emit GetFee(account, isGetFee);
    }

    function setFeeToDev(uint _feeToDev) public onlyAdmin {
        feeToDev = _feeToDev;
    }

    function setFeeToNull(uint _feeToNull) public onlyAdmin {
        feeToNull = _feeToNull;
    }

    function setTransferFee(uint256 _transferFee) public onlyOwner {
        transferFee = _transferFee;
    }

}