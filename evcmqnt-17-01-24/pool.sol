//SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "./ERC20.sol";
import "./IERC20.sol";
import "./Ownable.sol";
import "./Pausable.sol";
import "./ReentrancyGuard.sol";
import "./SafeERC20.sol";
import "./SafeMath.sol";


interface SwappedToken {

    function evcSwapVestByUser(address _user) external view returns(uint256);

}


contract Vest is Ownable, Pausable, ReentrancyGuard {

    using SafeMath for uint256;

    IERC20 private USDCToken;
    IERC20 private EVCToken;

    address private evcNFTToken;
    address private evcRouterAddress;

    uint256 private claimBarometerTime = 60;
    // uint256 private claimBarometerTime = 86400; //NOTE: Tokenomics

    mapping(address => bool) private hasCompletedClaim;
    mapping(address => uint256) private nextRedeemTimeForVestSwap;
    mapping(address => uint256) private redeemedValueForVestSwap;
    mapping(address => uint256) private RBLastClaimTime;

    event EVCTokensRBClaimed(address indexed account, uint256 amount);


    //Constructor
    constructor(address _usdcToken, address _evcToken) {
        USDCToken = IERC20(_usdcToken);
        EVCToken = IERC20(_evcToken);
    }

    function initialize(address _evc, address _nftaddress, address _evcRouter) public {
        setEVCToken(_evc);
        setEvcNFTToken(_nftaddress);
        setEvcRouterAddress(_evcRouter);
    }

    //User
    function claimVestRB() public nonReentrant whenNotPaused {
        require(nextRedeemTimeForVestSwap[msg.sender] < block.timestamp, "To claim vested, please wait until the next redeemable timing");
        uint256 swapEVCearning = SwappedToken(evcNFTToken).evcSwapVestByUser(msg.sender);
        uint256 totalClaimed = redeemedValueForVestSwap[msg.sender];
        uint256 rewardPercentage;
        require(totalClaimed < swapEVCearning, "you have no balance to claim");
        if (RBLastClaimTime[msg.sender] > 0) {
            if (hasCompletedClaim[msg.sender] == true) {
                rewardPercentage = 3;
                hasCompletedClaim[msg.sender] = false;
            } else {
                uint256 elapsedTime = block.timestamp.sub(RBLastClaimTime[msg.sender]);
                if (elapsedTime >= 60 && elapsedTime <= 599) {
                    rewardPercentage = uint(elapsedTime.div(60)).mul(3);
                } else if (elapsedTime >= 600) {
                    rewardPercentage = 100;
                    hasCompletedClaim[msg.sender] = true;
                }
                // if (elapsedTime >= 86400 && elapsedTime <= 2851199) { //NOTE: Tokenomics
                //     rewardPercentage = uint(elapsedTime / 86400) * 3;
                // } else if (elapsedTime >= 2851200) {
                //     rewardPercentage = 100;
                //     hasCompletedClaim[msg.sender] = true;
                // }
            }
        } else {
            rewardPercentage = 3;
        }
        uint256 swapEVCTotal = swapEVCearning.sub(totalClaimed);
        uint256 amountEVC = (swapEVCTotal.mul(rewardPercentage)).div(100);
        require(amountEVC > 0, "can't transfer zero tokens");
        EVCToken.transfer(msg.sender, amountEVC);
        redeemedValueForVestSwap[msg.sender] += amountEVC;
        nextRedeemTimeForVestSwap[msg.sender] = block.timestamp.add(claimBarometerTime);
        RBLastClaimTime[msg.sender] = block.timestamp;
        // EVCRouter(evcRouterAddress).setamountTokenToStable(msg.sender, amountEVC);
        emit EVCTokensRBClaimed(msg.sender, amountEVC);
    }

    //View
    function getElapsedTime(address _user) public view returns(uint256) {
        if (RBLastClaimTime[_user] == 0) {
            return 0;
        }
        if (hasCompletedClaim[msg.sender] == true) {
            return 0;
        }
        uint256 elapsedTime = block.timestamp.sub(RBLastClaimTime[_user]);
        return elapsedTime;
    }

    function getRemainingEVCAmountRB(address _user) public view returns(uint256) {
        uint256 swapEVCearning = SwappedToken(evcNFTToken).evcSwapVestByUser(_user);
        uint256 totalClaimed = redeemedValueForVestSwap[_user];
        uint256 swapEVCTotal = swapEVCearning.sub(totalClaimed);
        return swapEVCTotal;
    }

    function getRewardPercentageEVCRB(address _user) public view returns(uint256) {
        if (RBLastClaimTime[_user] == 0 || hasCompletedClaim[msg.sender] == true) {
            return 3;
        }
        uint256 elapsedTime = block.timestamp.sub(RBLastClaimTime[_user]);
        uint256 rewardPercentage;
        if (elapsedTime >= 1 && elapsedTime <= ((60 * 1) - 1)) {
            return 0;
        }
        if (elapsedTime >= (60 * 1) && elapsedTime <= ((60 * 2) - 1)) {
            rewardPercentage = 3;
        } else if (elapsedTime >= (60 * 2) && elapsedTime <= ((60 * 3) - 1)) {
            rewardPercentage = 6;
        } else if (elapsedTime >= (60 * 3) && elapsedTime <= ((60 * 4) - 1)) {
            rewardPercentage = 9;
        } else if (elapsedTime >= (60 * 4) && elapsedTime <= ((60 * 5) - 1)) {
            rewardPercentage = 12;
        } else if (elapsedTime >= (60 * 5) && elapsedTime <= ((60 * 6) - 1)) {
            rewardPercentage = 15;
        } else if (elapsedTime >= (60 * 6) && elapsedTime <= ((60 * 7) - 1)) {
            rewardPercentage = 18;
        } else if (elapsedTime >= (60 * 7) && elapsedTime <= ((60 * 8) - 1)) {
            rewardPercentage = 21;
        } else if (elapsedTime >= (60 * 8) && elapsedTime <= ((60 * 9) - 1)) {
            rewardPercentage = 24;
        } else if (elapsedTime >= (60 * 9) && elapsedTime <= ((60 * 10) - 1)) {
            rewardPercentage = 27;
        } else if (elapsedTime >= (60 * 10) && elapsedTime <= ((60 * 11) - 1)) {
            rewardPercentage = 30;
        } else if (elapsedTime >= (60 * 11) && elapsedTime <= ((60 * 12) - 1)) {
            rewardPercentage = 33;
        } else if (elapsedTime >= (60 * 12) && elapsedTime <= ((60 * 13) - 1)) {
            rewardPercentage = 36;
        } else if (elapsedTime >= (60 * 13) && elapsedTime <= ((60 * 14) - 1)) {
            rewardPercentage = 39;
        } else if (elapsedTime >= (60 * 14) && elapsedTime <= ((60 * 15) - 1)) {
            rewardPercentage = 42;
        } else if (elapsedTime >= (60 * 15) && elapsedTime <= ((60 * 16) - 1)) {
            rewardPercentage = 45;
        } else if (elapsedTime >= (60 * 16) && elapsedTime <= ((60 * 17) - 1)) {
            rewardPercentage = 48;
        } else if (elapsedTime >= (60 * 17) && elapsedTime <= ((60 * 18) - 1)) {
            rewardPercentage = 51;
        } else if (elapsedTime >= (60 * 18) && elapsedTime <= ((60 * 19) - 1)) {
            rewardPercentage = 54;
        } else if (elapsedTime >= (60 * 19) && elapsedTime <= ((60 * 20) - 1)) {
            rewardPercentage = 57;
        } else if (elapsedTime >= (60 * 20) && elapsedTime <= ((60 * 21) - 1)) {
            rewardPercentage = 60;
        } else if (elapsedTime >= (60 * 21) && elapsedTime <= ((60 * 22) - 1)) {
            rewardPercentage = 63;
        } else if (elapsedTime >= (60 * 22) && elapsedTime <= ((60 * 23) - 1)) {
            rewardPercentage = 66;
        } else if (elapsedTime >= (60 * 23) && elapsedTime <= ((60 * 24) - 1)) {
            rewardPercentage = 69;
        } else if (elapsedTime >= (60 * 24) && elapsedTime <= ((60 * 25) - 1)) {
            rewardPercentage = 72;
        } else if (elapsedTime >= (60 * 25) && elapsedTime <= ((60 * 26) - 1)) {
            rewardPercentage = 75;
        } else if (elapsedTime >= (60 * 26) && elapsedTime <= ((60 * 27) - 1)) {
            rewardPercentage = 78;
        } else if (elapsedTime >= (60 * 27) && elapsedTime <= ((60 * 28) - 1)) {
            rewardPercentage = 81;
        } else if (elapsedTime >= (60 * 28) && elapsedTime <= ((60 * 29) - 1)) {
            rewardPercentage = 84;
        } else if (elapsedTime >= (60 * 29) && elapsedTime <= ((60 * 30) - 1)) {
            rewardPercentage = 87;
        } else if (elapsedTime >= (60 * 30) && elapsedTime <= ((60 * 31) - 1)) {
            rewardPercentage = 90;
        } else if (elapsedTime >= (60 * 31) && elapsedTime <= ((60 * 32) - 1)) {
            rewardPercentage = 93;
        } else if (elapsedTime >= (60 * 32) && elapsedTime <= ((60 * 33) - 1)) {
            rewardPercentage = 96;
        } else if (elapsedTime >= (60 * 33)) {
            rewardPercentage = 100;
        }
        return rewardPercentage;
    }

    // function getRewardPercentageEVCRB(address _user) public view returns(uint256) { //NOTE: Tokenomics
    //     if (RBLastClaimTime[_user] == 0 || hasCompletedClaim[msg.sender] == true) {
    //         return 3;
    //     }
    //     uint256 elapsedTime = block.timestamp - RBLastClaimTime[_user];
    //     uint256 rewardPercentage;
    //     if (elapsedTime >= 1 && elapsedTime <= ((86400 * 1) - 1)) {
    //         return 0;
    //     }
    //     if (elapsedTime >= (86400 * 1) && elapsedTime <= ((86400 * 2) - 1)) {
    //         rewardPercentage = 3;
    //     } else if (elapsedTime >= (86400 * 2) && elapsedTime <= ((86400 * 3) - 1)) {
    //         rewardPercentage = 6;
    //     } else if (elapsedTime >= (86400 * 3) && elapsedTime <= ((86400 * 4) - 1)) {
    //         rewardPercentage = 9;
    //     } else if (elapsedTime >= (86400 * 4) && elapsedTime <= ((86400 * 5) - 1)) {
    //         rewardPercentage = 12;
    //     } else if (elapsedTime >= (86400 * 5) && elapsedTime <= ((86400 * 6) - 1)) {
    //         rewardPercentage = 15;
    //     } else if (elapsedTime >= (86400 * 6) && elapsedTime <= ((86400 * 7) - 1)) {
    //         rewardPercentage = 18;
    //     } else if (elapsedTime >= (86400 * 7) && elapsedTime <= ((86400 * 8) - 1)) {
    //         rewardPercentage = 21;
    //     } else if (elapsedTime >= (86400 * 8) && elapsedTime <= ((86400 * 9) - 1)) {
    //         rewardPercentage = 24;
    //     } else if (elapsedTime >= (86400 * 9) && elapsedTime <= ((86400 * 10) - 1)) {
    //         rewardPercentage = 27;
    //     } else if (elapsedTime >= (86400 * 10) && elapsedTime <= ((86400 * 11) - 1)) {
    //         rewardPercentage = 30;
    //     } else if (elapsedTime >= (86400 * 11) && elapsedTime <= ((86400 * 12) - 1)) {
    //         rewardPercentage = 33;
    //     } else if (elapsedTime >= (86400 * 12) && elapsedTime <= ((86400 * 13) - 1)) {
    //         rewardPercentage = 36;
    //     } else if (elapsedTime >= (86400 * 13) && elapsedTime <= ((86400 * 14) - 1)) {
    //         rewardPercentage = 39;
    //     } else if (elapsedTime >= (86400 * 14) && elapsedTime <= ((86400 * 15) - 1)) {
    //         rewardPercentage = 42;
    //     } else if (elapsedTime >= (86400 * 15) && elapsedTime <= ((86400 * 16) - 1)) {
    //         rewardPercentage = 45;
    //     } else if (elapsedTime >= (86400 * 16) && elapsedTime <= ((86400 * 17) - 1)) {
    //         rewardPercentage = 48;
    //     } else if (elapsedTime >= (86400 * 17) && elapsedTime <= ((86400 * 18) - 1)) {
    //         rewardPercentage = 51;
    //     } else if (elapsedTime >= (86400 * 18) && elapsedTime <= ((86400 * 19) - 1)) {
    //         rewardPercentage = 54;
    //     } else if (elapsedTime >= (86400 * 19) && elapsedTime <= ((86400 * 20) - 1)) {
    //         rewardPercentage = 57;
    //     } else if (elapsedTime >= (86400 * 20) && elapsedTime <= ((86400 * 21) - 1)) {
    //         rewardPercentage = 60;
    //     } else if (elapsedTime >= (86400 * 21) && elapsedTime <= ((86400 * 22) - 1)) {
    //         rewardPercentage = 63;
    //     } else if (elapsedTime >= (86400 * 22) && elapsedTime <= ((86400 * 23) - 1)) {
    //         rewardPercentage = 66;
    //     } else if (elapsedTime >= (86400 * 23) && elapsedTime <= ((86400 * 24) - 1)) {
    //         rewardPercentage = 69;
    //     } else if (elapsedTime >= (86400 * 24) && elapsedTime <= ((86400 * 25) - 1)) {
    //         rewardPercentage = 72;
    //     } else if (elapsedTime >= (86400 * 25) && elapsedTime <= ((86400 * 26) - 1)) {
    //         rewardPercentage = 75;
    //     } else if (elapsedTime >= (86400 * 26) && elapsedTime <= ((86400 * 27) - 1)) {
    //         rewardPercentage = 78;
    //     } else if (elapsedTime >= (86400 * 27) && elapsedTime <= ((86400 * 28) - 1)) {
    //         rewardPercentage = 81;
    //     } else if (elapsedTime >= (86400 * 28) && elapsedTime <= ((86400 * 29) - 1)) {
    //         rewardPercentage = 84;
    //     } else if (elapsedTime >= (86400 * 29) && elapsedTime <= ((86400 * 30) - 1)) {
    //         rewardPercentage = 87;
    //     } else if (elapsedTime >= (86400 * 30) && elapsedTime <= ((86400 * 31) - 1)) {
    //         rewardPercentage = 90;
    //     } else if (elapsedTime >= (86400 * 31) && elapsedTime <= ((86400 * 32) - 1)) {
    //         rewardPercentage = 93;
    //     } else if (elapsedTime >= (86400 * 32) && elapsedTime <= ((86400 * 33) - 1)) {
    //         rewardPercentage = 96;
    //     } else if (elapsedTime >= (86400 * 33)) {
    //         rewardPercentage = 100;
    //     }
    //     return rewardPercentage;
    // }


    function getUserRedeemValuevestSwap(address user) public view returns(uint) {
        return redeemedValueForVestSwap[user];
    }

    //Admin
    function pause() public onlyOwner {
        _pause();
    }

    function setClaimBarometerTime(uint256 _claimBarometerTime) public onlyOwner {
        claimBarometerTime = _claimBarometerTime;
    }

    function setEvcNFTToken(address _evcNFTToken) public onlyOwner {
        evcNFTToken = _evcNFTToken;
    }

    function setEvcRouterAddress(address _evcRouter) public onlyOwner {
        evcRouterAddress = _evcRouter;
    }

    function setEVCToken(address _EVCToken) public onlyOwner {
        EVCToken = IERC20(_EVCToken);
    }

    function unpause() public onlyOwner {
        _unpause();
    }

    function withdrawUSDC(address _to, uint256 _amount) public onlyOwner {
        require(_amount > 0, "Transfer amount must be greater than zero");
        USDCToken.transfer(_to, _amount); // Use transfer instead of safeTransfer for BEP20 tokens
    }

    function withdrawEVC(address _to, uint256 _amount) public onlyOwner {
        require(_amount > 0, "Transfer amount must be greater than zero");
        EVCToken.transfer(_to, _amount);
    }

    receive() external payable {}

    fallback() external payable {}

}