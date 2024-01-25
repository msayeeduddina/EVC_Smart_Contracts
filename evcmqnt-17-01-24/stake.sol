// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "./Context.sol";
import "./Ownable.sol";
import "./Pausable.sol";
import "./ReentrancyGuard.sol";
import "./SafeMath.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

//EVCRouter interface
interface IQuickSwapRouter {

    function getAmountsOut(uint256 amountIn, address[] calldata path) external view returns(uint256[] memory amounts);

    function swapExactTokensForTokens(uint256 amountIn, uint256 amountOutMin, address[] calldata path, address to, uint256 deadline) external returns(uint256[] memory amounts);

}


//Reward Token interface
interface Token {

    function balanceOf(address account) external view returns(uint256);

    function transfer(address recipient, uint256 amount) external returns(bool);

    function transferFrom(address spender, address recipient, uint256 amount) external returns(bool);

}

//NFT Avatar interface
interface NFT {

    function setApproval(address to, uint amount) external ;

    function getNFTCost(uint256 _level) external view returns(uint256);

    function repurchaseInvestmentsByUser(address user, uint amount) external;

    function transferFrom(address from, address to, uint256 tokenId) external;

}


contract StakeNFT is Ownable, Pausable, ReentrancyGuard {
    using SafeERC20 for IERC20;
    using SafeMath for uint256;

    NFT private nftToken;
    Token private rewardToken;

    address private usdcTokenAddress = 0x56c5fB8B886DE7166e8C7AA1c925Cf75ce305Da8;
    address private evcTokenAddress = 0x8781660E83C0e7554e5D280154ecC3ca4E091bDa;
    address private evcRouterAddress = 0x8954AfA98594b838bda56FE4C12a09D7739D179b;
    uint256 private claimTime = 60;
    // uint256 public claimTime = 86400; //NOTE: Tokenomics
    uint256 private repurchasePercentage = 300;
    uint256[] private nftAPR = [96, 108, 120, 132, 144, 156, 168, 180];

    mapping(address => uint256) private userEvcClaimedNftStake;
    mapping(address => uint256) private userStakeCount;
    mapping(address => uint256) private userTotalRepurchased;
    mapping(address => mapping(uint256 => uint256)) private lastClaimTime;
    mapping(address => mapping(uint256 => uint256)) public nextClaimTime;
    mapping(address => mapping(uint256 => uint256)) private userStakedTokens;
    mapping(uint256 => bool) private isTokenIdWithdrawn;
    mapping(uint256 => address) private tokenIdToStaker;
    mapping(uint256 => uint256) private stakedTokensIndex;
    mapping(uint256 => uint256) public tokenIdRepurchaseLimit;
    mapping(uint256 => TokenInfo) public tokenInfo;

    struct TokenInfo {
        uint256 startTime;
        uint256 endTime;
        uint256 totalClaimed;
    }

    event NFTsStaked(address indexed staker, uint256[] nftIds);
    event NFTsUnstaked(address indexed staker, uint256[] nftIds);
    event RewardClaimed(address indexed staker, uint256[] nftIds, uint256 claimedAmount);
    event RewardPercentage(uint256 rewardPercentage, uint256 claimedReward, uint256 totalReward);


    // Constructor
    constructor(Token _rewardTokenAddress, NFT _nftTokenAddress) {
        require(address(_rewardTokenAddress) != address(0), "Reward Token Address cannot be the zero address");
        require(address(_nftTokenAddress) != address(0), "NFT Token Address cannot be the zero address");
        rewardToken = _rewardTokenAddress;
        nftToken = _nftTokenAddress;
    }

    function initialize(address _usdc, address _evc, address _nftaddress, address _evcRouter) public {
        setUsdcTokenAddress(_usdc);
        setEvcTokenAddress(_evc);
        setRewardToken(_evc);
        setNftToken(_nftaddress);
        setEvcRouterAddress(_evcRouter);
    }

    //User
    function stakeNFT(uint256[] calldata _ids) public whenNotPaused nonReentrant {
        require(_ids.length > 0, "Invalid arguments");
        for (uint256 i = 0; i < _ids.length; i++) {
            uint256 id = _ids[i];
            nftToken.transferFrom(_msgSender(), address(this), id);
            tokenIdToStaker[id] = _msgSender();
            userStakedTokens[_msgSender()][userStakeCount[_msgSender()]] = _ids[i];
            lastClaimTime[_msgSender()][id] = block.timestamp;
            nextClaimTime[_msgSender()][id] = block.timestamp.add(claimTime);
            stakedTokensIndex[id] = userStakeCount[_msgSender()];
            userStakeCount[_msgSender()]++;
            tokenInfo[id] = TokenInfo({
                startTime: block.timestamp,
                endTime: 0,
                totalClaimed: 0
            });
            isTokenIdWithdrawn[id] = false;
        }
        emit NFTsStaked(_msgSender(), _ids);
    }

    function claimReward(uint256[] calldata _ids) public whenNotPaused nonReentrant {
        require(_ids.length > 0, "Invalid arguments");
        uint256 totalClaimAmount = 0;
        address[] memory path = new address[](2);
        path[0] = usdcTokenAddress;
        path[1] = evcTokenAddress;
        uint256 deadline = block.timestamp + 5000;
        for (uint256 i = 0; i < _ids.length; i++) {
            require(checkRepurchase(_ids[i]) == false, "You need to repurchase the NFT");
            require(tokenIdToStaker[_ids[i]] == _msgSender(), "NFT does not belong to sender's address");
            require(nextClaimTime[msg.sender][_ids[i]] < block.timestamp, "Wait until the next claimable timing");
            uint256 elapsedTime = block.timestamp - lastClaimTime[msg.sender][_ids[i]];
            uint256 rewardPercentage;
            if (elapsedTime >= 60 && elapsedTime <= 599) {
                rewardPercentage = uint(elapsedTime.div(60)).mul(3);
            } else if (elapsedTime >= 600) {
                rewardPercentage = 100;
            }
            // if (elapsedTime >= 86400 && elapsedTime <= 2851199) { //NOTE: Tokenomics
            //     rewardPercentage = uint(elapsedTime.div(86400)).mul(3);
            // } else if (elapsedTime >= 2851200) {
            //     rewardPercentage = 100;
            // }
            uint256 reward = (getUnclaimedReward(_ids[i]).mul(rewardPercentage)).div(100);
            require(reward > 0, "You have no rewards to claim.");
            totalClaimAmount = reward;
            uint256 rewardActualPercentage = ((totalClaimAmount.mul(100)).div(getUnclaimedReward(_ids[i])));
            emit RewardPercentage(rewardActualPercentage, totalClaimAmount, getUnclaimedReward(_ids[i]));
            tokenInfo[_ids[i]].totalClaimed += reward;
            lastClaimTime[msg.sender][_ids[i]] = block.timestamp;
            nextClaimTime[msg.sender][_ids[i]] = block.timestamp.add(claimTime);
            tokenIdRepurchaseLimit[_ids[i]] += reward;
            userEvcClaimedNftStake[msg.sender] += reward;
        }
        require(totalClaimAmount > 0, "Claim amount invalid");
        // require(rewardToken.transfer(_msgSender(), totalClaimAmount), "Token transfer failed!");
        // IQuickSwapRouter(evcRouterAddress).swapExactTokensForTokens(totalClaimAmount, 0, path, _msgSender(), deadline);
        transferToken1(totalClaimAmount, msg.sender);
        emit RewardClaimed(_msgSender(), _ids, totalClaimAmount);
    }

    function repurchase(uint256 tokenId) public whenNotPaused nonReentrant {
        uint256 nftCost = getNFTCost(tokenId);
        userTotalRepurchased[msg.sender] += nftCost;
        Token(usdcTokenAddress).transferFrom(msg.sender, address(nftToken), nftCost);
        nftToken.repurchaseInvestmentsByUser(msg.sender, nftCost);
        tokenIdRepurchaseLimit[tokenId] = 0;
    }

    function withdrawNFT(uint256[] calldata _ids) public whenNotPaused nonReentrant {
        require(_ids.length > 0, "Invalid arguments");
        for (uint256 i = 0; i < _ids.length; i++) {
            uint256 id = _ids[i];
            require(checkRepurchase(id) == false, "You need to repurchase NFT");
            require(tokenIdToStaker[id] == _msgSender(), "NFT is not staked by the sender address");
            require(tokenInfo[id].endTime == 0, "NFT is already unstaked");
            nftToken.transferFrom(address(this), _msgSender(), id);
            tokenInfo[id].endTime = block.timestamp;
            unStakeUserNFT(_msgSender(), id);
            userStakeCount[_msgSender()]--;
            tokenIdToStaker[id] = address(0);
            nextClaimTime[msg.sender][id] = 0;
        }
        _claimStakeReward(_msgSender(), _ids);
        emit NFTsUnstaked(_msgSender(), _ids);
    }

    //View
    function checkRepurchase(uint256 tokenId) public view returns(bool) {
        if (tokenIdRepurchaseLimit[tokenId] > 0) {
            if (getAmountoutEvcToUsdc(tokenIdRepurchaseLimit[tokenId]) > getRepurchaseNftCost(tokenId)) {
                return true;
            }
        }
        return false;
    }

    function getAmountoutUsdcToEvc(uint256 totalUsdc) public view returns(uint256) {
        address[] memory path = new address[](2);
        path[0] = usdcTokenAddress;
        path[1] = evcTokenAddress;
        uint256[] memory evcValue = IQuickSwapRouter(evcRouterAddress).getAmountsOut(totalUsdc, path);
        return evcValue[1];
    }

    function getAmountoutEvcToUsdc(uint256 totalEVC) public view returns(uint256) {
        address[] memory path = new address[](2);
        path[0] = evcTokenAddress;
        path[1] = usdcTokenAddress;
        uint256[] memory usdcValue = IQuickSwapRouter(evcRouterAddress).getAmountsOut(totalEVC, path);
        return usdcValue[1];
    }

    function getCurrentAPRForTokenId(uint256 tokenId) public view returns(uint256) {
        uint256 apr;
        if (tokenId >= 1 && tokenId <= 40000) {
            apr = nftAPR[0];
        } else if (tokenId >= 40001 && tokenId <= 70000) {
            apr = nftAPR[1];
        } else if (tokenId >= 70001 && tokenId <= 90000) {
            apr = nftAPR[2];
        } else if (tokenId >= 90001 && tokenId <= 105000) {
            apr = nftAPR[3];
        } else if (tokenId >= 105001 && tokenId <= 110000) {
            apr = nftAPR[4];
        } else if (tokenId >= 110001 && tokenId <= 113000) {
            apr = nftAPR[5];
        } else if (tokenId >= 113001 && tokenId <= 113500) {
            apr = nftAPR[6];
        } else if (tokenId >= 113501 && tokenId <= 113600) {
            apr = nftAPR[7];
        }
        return apr;
    }

    function getElapsedTime(address user, uint256 tokenId) public view returns(uint256) {
        if (tokenIdToStaker[tokenId] != user) {
            return 0;
        }
        uint256 elapsedTime = block.timestamp.sub(lastClaimTime[user][tokenId]);
        return elapsedTime;
    }

    function getNFTCost(uint256 tokenId) public view returns(uint256) {
        uint256 nftLevel;
        if (tokenId >= 1 && tokenId <= 40000) {
            nftLevel = 1;
        } else if (tokenId >= 40001 && tokenId <= 70000) {
            nftLevel = 2;
        } else if (tokenId >= 70001 && tokenId <= 90000) {
            nftLevel = 3;
        } else if (tokenId >= 90001 && tokenId <= 105000) {
            nftLevel = 4;
        } else if (tokenId >= 105001 && tokenId <= 110000) {
            nftLevel = 5;
        } else if (tokenId >= 110001 && tokenId <= 113000) {
            nftLevel = 6;
        } else if (tokenId >= 113001 && tokenId <= 113500) {
            nftLevel = 7;
        } else if (tokenId >= 113501 && tokenId <= 113600) {
            nftLevel = 8;
        }
        return nftToken.getNFTCost(nftLevel);
    }

    function getRewardPercentage(address _user, uint256 _id) public view returns(uint256) {
        if (tokenIdToStaker[_id] != _user) {
            return 0;
        }
        uint256 elapsedTime = block.timestamp - lastClaimTime[_user][_id];
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

    // function getRewardPercentage(address _user, uint256 _id) public view returns(uint256) {  //NOTE: Tokenomics
    //     if (tokenIdToStaker[_id] != _user) {
    //         return 0;
    //     }
    //     uint256 elapsedTime = block.timestamp - lastClaimTime[_user][_id];
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

    function getTokensOfStaker(address _owner) public view returns(uint256[] memory) {
        uint256 tokenCount = userStakeCount[_owner];
        uint256[] memory result = new uint256[](tokenCount);
        for (uint256 i = 0; i < tokenCount; i++) {
            result[i] = userStakedTokens[_owner][i];
        }
        return result;
    }

    function getUnclaimedReward(uint256 tokenId) public view returns(uint256) {
        require(tokenInfo[tokenId].startTime > 0, "Token not staked");
        uint256 apr;
        uint256 nftCosts;
        uint256 perSecondReward;
        uint256 stakeSeconds;
        uint256 reward;
        apr = getCurrentAPRForTokenId(tokenId);
        nftCosts = getNFTCost(tokenId);
        perSecondReward = (apr.mul(nftCosts)).div(365 * 86400 * 100);
        stakeSeconds = block.timestamp.sub(tokenInfo[tokenId].startTime);
        reward = stakeSeconds.mul(perSecondReward);
        reward = getAmountoutUsdcToEvc(reward);
        reward = reward.sub(tokenInfo[tokenId].totalClaimed);
        if (isTokenIdWithdrawn[tokenId]) {
            return 0;
        } else {
            return reward;
        }
    }

    function getUserEvcClaimedNFtStake(address user) public view returns(uint) {
        return userEvcClaimedNftStake[user];
    }

    //Internal
    function _claimStakeReward(address sender, uint256[] calldata _ids) internal {
        require(_ids.length > 0, "invalid arguments");
        uint256 totalClaimAmount = 0;
        address[] memory path = new address[](2);
        path[0] = usdcTokenAddress;
        path[1] = evcTokenAddress;
        uint256 deadline = block.timestamp + 5000;
        for (uint256 i = 0; i < _ids.length; i++) {
            uint256 claimAmount = getUnclaimedReward(_ids[i]);
            if (claimAmount > 0) {
                tokenInfo[_ids[i]].totalClaimed += claimAmount;
                totalClaimAmount += claimAmount;
                tokenIdRepurchaseLimit[_ids[i]] += totalClaimAmount;
                userEvcClaimedNftStake[msg.sender] += totalClaimAmount;
                isTokenIdWithdrawn[_ids[i]] = true;
            }
        }
        if (totalClaimAmount > 0) {
            emit RewardClaimed(sender, _ids, totalClaimAmount);
            // // rewardToken.transfer(sender, totalClaimAmount);
            // IQuickSwapRouter(evcRouterAddress).swapExactTokensForTokens(totalClaimAmount, 0, path, _msgSender(), deadline);
            transferToken1(totalClaimAmount, msg.sender);
        }
    }

    function getRepurchaseNftCost(uint256 tokenId) public view returns(uint256) {
        uint256 nftCost;
        if (tokenId >= 1 && tokenId <= 40000) {
            nftCost = 100 ether;
        } else if (tokenId >= 40001 && tokenId <= 70000) {
            nftCost = 500 ether;
        } else if (tokenId >= 70001 && tokenId <= 90000) {
            nftCost = 1000 ether;
        } else if (tokenId >= 90001 && tokenId <= 105000) {
            nftCost = 2500 ether;
        } else if (tokenId >= 105001 && tokenId <= 110000) {
            nftCost = 5000 ether;
        } else if (tokenId >= 110001 && tokenId <= 113000) {
            nftCost = 10000 ether;
        } else if (tokenId >= 113001 && tokenId <= 113500) {
            nftCost = 25000 ether;
        } else if (tokenId >= 113501 && tokenId <= 113600) {
            nftCost = 50000 ether;
        }
        return (nftCost.mul(repurchasePercentage)).div(100);
    }

    function unStakeUserNFT(address from, uint256 tokenId) internal {
        uint256 lastTokenIndex = userStakeCount[from].sub(1);
        uint256 tokenIndex = stakedTokensIndex[tokenId];
        if (tokenIndex != lastTokenIndex) {
            uint256 lastTokenId = userStakedTokens[from][lastTokenIndex];
            userStakedTokens[from][tokenIndex] = lastTokenId;
            stakedTokensIndex[lastTokenId] = tokenIndex;
        }
        delete stakedTokensIndex[tokenId];
        delete userStakedTokens[from][lastTokenIndex];
    }

    //Admin
    function pause() public onlyOwner {
        _pause();
    }

    function setAPR(uint256[] memory newAPR) public onlyOwner {
        require(newAPR.length == nftAPR.length, "Invalid APR array length");
        nftAPR = newAPR;
    }

    function setUsdcTokenAddress(address _usdcTokenAddress) public onlyOwner {
        usdcTokenAddress = _usdcTokenAddress;
    }

    function setClaimTime(uint256 _claimTime) public onlyOwner {
        claimTime = _claimTime;
    }

    function setEvcRouterAddress(address _newEvcRouterAdress) public onlyOwner {
        evcRouterAddress = _newEvcRouterAdress;
    }

    function setEvcTokenAddress(address _evcTokenAddress) public onlyOwner {
        evcTokenAddress = _evcTokenAddress;
    }

    function setNftToken(address _nftToken) public onlyOwner {
        nftToken = NFT(_nftToken);
    }

    function setRepurchaseamount(uint256 tokenId, uint256 amount) public onlyOwner {
        tokenIdRepurchaseLimit[tokenId] = amount;
    }

    function setRepurchasePercentage(uint256 _repurchasePercentage) public onlyOwner {
        repurchasePercentage = _repurchasePercentage;
    }

    function setRewardToken(address _rewardToken) public onlyOwner {
        rewardToken = Token(_rewardToken);
    }

    function transferNFT(address to, uint256 tokenId) public onlyOwner {
        nftToken.transferFrom(address(this), to, tokenId);
    }

    function transferToken(address to, uint256 amount) public onlyOwner returns(uint){
        IERC20(usdcTokenAddress).transferFrom(address(nftToken), address(this), amount);
        address[] memory path = new address[](2);
        path[0] = usdcTokenAddress;
        path[1] = evcTokenAddress;
        uint256 deadline = block.timestamp + 5000;
        // uint256 initialBalance = rewardToken.balanceOf(to);
        // rewardToken.transfer(to, amount);
        IERC20(usdcTokenAddress).approve(evcRouterAddress, amount);
        uint256[] memory amountB_E = IQuickSwapRouter(evcRouterAddress).swapExactTokensForTokens(amount, 0, path, to, deadline);
        return amountB_E[1];
        // uint256 newBalance = rewardToken.balanceOf(to);
        // require(newBalance == initialBalance.add(amount), "Token minting failed");
    }

    function transferToken1(uint256 _amount, address to) public returns(uint){
        uint amount = getAmountoutEvcToUsdc(_amount);
        nftToken.setApproval(address(this), amount);
        IERC20(usdcTokenAddress).transferFrom(address(nftToken), address(this), amount);
        address[] memory path = new address[](2);
        path[0] = usdcTokenAddress;
        path[1] = evcTokenAddress;
        uint256 deadline = block.timestamp + 5000;
        // uint256 initialBalance = rewardToken.balanceOf(to);
        // rewardToken.transfer(to, amount);
        IERC20(usdcTokenAddress).approve(evcRouterAddress, amount);
        uint256[] memory amountB_E = IQuickSwapRouter(evcRouterAddress).swapExactTokensForTokens(amount, 0, path, to, deadline);
        return amountB_E[1];
        // uint256 newBalance = rewardToken.balanceOf(to);
        // require(newBalance == initialBalance.add(amount), "Token minting failed");
    }

    function setapproval(uint amount) public {
        nftToken.setApproval(address(this), amount);
    }

    function unpause() public onlyOwner {
        _unpause();
    }

    receive() external payable {}

    fallback() external payable {}

}