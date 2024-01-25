// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "./Counters.sol";
import "./ERC721.sol";
import "./ERC721Enumerable.sol";
import "./Ownable.sol";
import "./ReentrancyGuard.sol";
import "./SafeERC20.sol";
import "./SafeMath.sol";
import "./Strings.sol";


interface IEVCRouter {

    function getAmountsOut(uint256 amountIn, address[] calldata path) external returns(uint256[] memory amounts);

    function swapExactTokensForTokens(uint256 amountIn, uint256 amountOutMin, address[] calldata path, address to, uint256 deadline) external returns(uint256[] memory amounts);

}


contract Avtars is Ownable, ERC721Enumerable, ReentrancyGuard {

    using Counters for Counters.Counter;
    using SafeERC20 for IERC20;
    using SafeMath for uint256;
    using Strings for uint256;

    address private usdcToken = 0x56c5fB8B886DE7166e8C7AA1c925Cf75ce305Da8;
    address private delegateAddress = 0x1856Cf49B13f3F7EAf3994fD1102347B50222902;
    address private evcRouterAdress = 0x8954AfA98594b838bda56FE4C12a09D7739D179b;
    address private token0 = 0x56c5fB8B886DE7166e8C7AA1c925Cf75ce305Da8; //usdc
    address private token1 = 0x8781660E83C0e7554e5D280154ecC3ca4E091bDa; //evc
    address private vestContract = 0x0B8089fF9deE79F5CfB64bAfdbCAc2E879d2EF9d;
    address[] private usersMinted;

    uint256[8] private nftMintCosts = [100 ether, 500 ether, 1000 ether, 2500 ether, 5000 ether, 10000 ether, 25000 ether, 50000 ether];
    uint256[8] private nftQuantities = [40000, 30000, 20000, 15000, 5000, 3000, 500, 100];
    uint256[] private evcBurnTimestamps;
    uint256[] private mintedNFTLevels;
    uint256 public totalPaidUniLevelRewards;

    string public baseExtension = ".json";
    string public baseURI = "ipfs://bafybeigsk6stfel5te26ni6cgo4qpxch3phz3szpummtrbxogpmoal2saa/";

    bool private delegate = false;
    bool public paused = false;

    mapping(address => bool)[8] public hasNFTs;
    mapping(address => bool) public isWhitelisted;
    mapping(address => uint256) private referralCounts;
    mapping(address => address) private referrerForAddress;
    mapping(address => address[]) private addressReferrals;
    mapping(address => mapping(uint256 => uint256)) private userDetailsByLevel;
    mapping(address => uint256) private investmentsByUser;
    mapping(address => uint256) private joinTimestamp;
    mapping(address => uint256) public unilevelEarningsByUser;
    mapping(address => uint256) public rankBonusEarningsByUser;
    mapping(address => uint256) public evcSwapVestByUser;
    mapping(address => uint256[]) private ownedNFTsByUser;
    mapping(uint256 => BurnData) private evcBurnDataByTimestamp;
    mapping(address => ReferralBonus) private transfersToVestByAddress;
    mapping(address => UserRank) private userRanks; ////{Decentralized}////

    struct BurnData {
        uint256 cumulativeBurnAmount;
        uint256 timestamp;
    }

    struct MintLevel {
        uint256 level;
        uint256 timestamp;
    }

    struct ReferralBonus {
        address referrer;
        uint256 evcTransferAmount;
        address vestContract;
    }

    struct UnilevelPrecentage {
        address referrer;
        uint256 percentage;
    }

    struct ReferrerDetails {
        address referrer;
        uint256 rank;
        uint256 percentage;
    }

    struct ShareUniReward {
        address[] users;
        uint percentage;
        bool agreed;
    }
    mapping(address => ShareUniReward) public shareUniReward;

    ////{Decentralized}////
    struct TeamStatistics {
        address userAddress;
        uint256 userRank;
        uint256 totalPartners;
        string nftLevel;
        uint256 totalTeamSales;
    }

    struct UserRank {
        uint256 rank;
        bool rankChanged;
    }
    ////////

    Counters.Counter[8] private nftCounters;

    // event Burn(address indexed recipient, uint256 amount);
    // event EVCSwapVestByUser(uint256 swappedAmounts);
    // event DirectReferralRewardTransferred(address indexed user, address directReferrer, uint256 rewardAmount);
    // event IndirectReferralRewardTransferred(address indexed user, address indirectReferrer, uint256 rewardAmount);


    //Constructor
    constructor(
        string memory _name,
        string memory _symbol
    ) ERC721(_name, _symbol) {
        nftCounters[1]._value = 40000;
        nftCounters[2]._value = 70000;
        nftCounters[3]._value = 90000;
        nftCounters[4]._value = 105000;
        nftCounters[5]._value = 110000;
        nftCounters[6]._value = 113000;
        nftCounters[7]._value = 113500;
    }


    function initialize(address _usdc, address _evc, address _evcRouter, address _vest) public {
        setUSDCToken(_usdc);
        setToken0(_usdc);
        setToken1(_evc);
        setEVCRouterAdress(_evcRouter);
        setVestContract(_vest);
    }

    //User
    ////{Decentralized}////    
    function mintNFT(uint256 _level, uint256 _mintPrice, bool _delegate, address _referrer) public nonReentrant {
        uint256 level = _level.sub(1);
        uint256 mintPrice = _mintPrice;
        require(level >= 0 && level <= 7, "Invalid NFT level");
        require(!hasNFTs[level][msg.sender], "You already have an NFT of this level!");
        require(!paused, "Minting is paused");
        require(totalSupplyOfLevel(_level) < nftQuantities[level], "Cannot mint more NFTs of this level");
        setReferrer(_referrer);
        uint256 requiredPrice = nftMintCosts[level];
        if (msg.sender != owner() && !isWhitelisted[msg.sender]) {
            IERC20(usdcToken).safeTransferFrom(msg.sender, address(this), mintPrice);
            if (_delegate) {
                uint256 sharePrice = requiredPrice.mul(10).div(100);
                uint256 newMintPrice = requiredPrice.add(sharePrice);
                require(mintPrice >= newMintPrice, "Insufficient payment amount; if delegate is true, add 10% more.");
                uint256 shareToDelegate = mintPrice.sub(requiredPrice);
                IERC20(usdcToken).transfer(delegateAddress, shareToDelegate);
                unilevelReward(msg.sender, requiredPrice);
            } else {
                require(mintPrice >= requiredPrice, "Insufficient payment amount");
                unilevelReward(msg.sender, requiredPrice);
            }
        }
        usdcAndEvcRankBonus(msg.sender, requiredPrice);
        buyandBurnPercentage(15, requiredPrice);
        nftCounters[level].increment();
        uint256 tokenId = nftCounters[level].current();
        investmentsByUser[msg.sender] += requiredPrice;
        _safeMint(msg.sender, tokenId);
        ownedNFTsByUser[msg.sender].push(tokenId);
        hasNFTs[level][msg.sender] = true;
        usersMinted.push(msg.sender);
        mintedNFTLevels.push(_level);
        userDetailsByLevel[msg.sender][_level] = block.timestamp;
    }
    ////////

    ////{Centralized}////
    // function mintNFT(uint256 _level, uint256 _mintPrice, bool _delegate, address _referrer) public {
    //     uint256 level = _level - 1;
    //     uint256 mintPrice = _mintPrice;
    //     require(level >= 0 && level <= 7, "Invalid NFT level");
    //     require(!hasNFTs[level][msg.sender], "You already have an NFT of this level!");
    //     require(!paused, "Minting is paused");
    //     require(totalSupplyOfLevel(_level) < nftQuantities[level], "Cannot mint more NFTs of this level");
    //     setReferrer(_referrer); // constant referrer
    //     uint256 requiredPrice = nftMintCosts[level];
    //     if (msg.sender != owner() && !isWhitelisted[msg.sender]) {
    //         address directReferrer = _referrer;
    //         address indirectReferrer = getReferrerOf(_referrer);
    //         uint256 directReferralReward = requiredPrice / 10;
    //         uint256 indirectReferralReward = requiredPrice * 5 / 100;
    //         IERC20(usdcToken).safeTransferFrom(msg.sender, address(this), mintPrice);
    //         if (_delegate) {
    //             uint256 sharePrice = requiredPrice * 10 / 100;
    //             uint256 newMintPrice = requiredPrice + sharePrice;
    //             require(mintPrice >= newMintPrice, "Insufficient payment amount; if delegate is true, add 10% more.");
    //             uint256 shareToDelegate = mintPrice - requiredPrice;
    //             IERC20(usdcToken).transfer(delegateAddress, shareToDelegate); //delegate removed out of if block
    //             if (indirectReferrer != address(0)) {
    //                 IERC20(usdcToken).transfer(indirectReferrer, indirectReferralReward);
    //                 unilevelEarningsByUser[indirectReferrer] += indirectReferralReward; // unilevel
    //                 IERC20(usdcToken).transfer(directReferrer, directReferralReward);
    //                 unilevelEarningsByUser[directReferrer] += directReferralReward; // unilevel
    //                 emit indirectReferralRewardTransferred(msg.sender, indirectReferrer, indirectReferralReward);
    //             } else if (directReferrer != address(0)) {
    //                 IERC20(usdcToken).transfer(directReferrer, directReferralReward);
    //                 unilevelEarningsByUser[directReferrer] += directReferralReward; // unilevel
    //                 emit directReferralRewardTransferred(msg.sender, directReferrer, directReferralReward);
    //             }
    //         } else {
    //             require(mintPrice >= requiredPrice, "Insufficient payment amount");
    //             if (indirectReferrer != address(0)) {
    //                 IERC20(usdcToken).transfer(indirectReferrer, indirectReferralReward);
    //                 unilevelEarningsByUser[indirectReferrer] += indirectReferralReward; // unilevel
    //                 IERC20(usdcToken).transfer(directReferrer, directReferralReward);
    //                 unilevelEarningsByUser[directReferrer] += directReferralReward; // unilevel
    //                 emit indirectReferralRewardTransferred(msg.sender, indirectReferrer, indirectReferralReward);
    //             } else if (directReferrer != address(0)) {
    //                 IERC20(usdcToken).transfer(directReferrer, directReferralReward);
    //                 unilevelEarningsByUser[directReferrer] += directReferralReward; // unilevel
    //                 emit directReferralRewardTransferred(msg.sender, directReferrer, directReferralReward);
    //             }
    //         }
    //     }
    //     nftCounters[level].increment();
    //     uint256 tokenId = nftCounters[level].current();
    //     investmentsByUser[msg.sender] += requiredPrice;
    //     _safeMint(msg.sender, tokenId);
    //     ownedNFTsByUser[msg.sender].push(tokenId);
    //     hasNFTs[level][msg.sender] = true;
    //     usersMinted.push(msg.sender);
    //     mintedNFTLevels.push(_level);
    //     userDetailsByLevel[msg.sender][_level] = block.timestamp;
    // }

    // function mintNFT1(uint256 _level, uint256 _mintPrice, bool _delegate, address _referrer, address[] memory rbmembers, uint256[] memory rbpercentages) public {
    //     mintNFT(_level, _mintPrice, _delegate, _referrer);
    //     uint256 requiredPrice = nftMintCosts[_level - 1];
    //     usdcAndEvcRankBonus(rbmembers, rbpercentages, requiredPrice);
    //     buyandBurnPercentage(15, requiredPrice);
    // }
    ////////

    //View
    ////{Decentralized}////    
    function checkUserRank(address _user) public view returns(uint256 _rank) {
        if (userRanks[_user].rankChanged) {
            return userRanks[_user].rank; // Return the cached user rank if it has changed
        }
        uint256 teamSaleVolume = getTotalTeamSaleVolume(_user);
        // Check if the user has specific NFTs and meets certain conditions to determine their rank
        if (hasNFTs[6][_user] && teamSaleVolume >= 700 ether && getRankUplifting(_user, 5, 5)) {
            return 7;
        }
        if (hasNFTs[5][_user] && teamSaleVolume >= 600 ether && getRankUplifting(_user, 4, 4)) {
            return 6;
        }
        if (hasNFTs[4][_user] && teamSaleVolume >= 500 ether && getRankUplifting(_user, 3, 3)) {
            return 5;
        }
        if (hasNFTs[3][_user] && teamSaleVolume >= 400 ether && getRankUplifting(_user, 2, 2)) {
            return 4;
        }
        if (hasNFTs[2][_user] && teamSaleVolume >= 300 ether && getRankUplifting(_user, 1, 1)) {
            return 3;
        }
        if (hasNFTs[1][_user] && teamSaleVolume >= 200 ether && getRankUplifting(_user, 0, 0)) {
            return 2;
        }
        if (hasNFTs[0][_user] && teamSaleVolume >= 100 ether) {
            return 1;
        }
    }
    ////////

    function getDirectReferrals(address referrer) public view returns(address[] memory) {
        return addressReferrals[referrer];
    }

    // function getMintedLevelsByTime(address user, uint256 timeFrom, uint256 timeTo) public view returns(LevelMint[] memory) {
    //     require(timeFrom <= timeTo, "Invalid time range");
    //     LevelMint[] memory levels = new LevelMint[](8);
    //     uint256 count = 0;
    //     for (uint256 i = 1; i <= 8; i++) {
    //         uint256 timeMinted = userDetailsByLevel[user][i];
    //         if (timeMinted >= timeFrom && timeMinted <= timeTo) {
    //             LevelMint memory mint = LevelMint(i, timeMinted);
    //             levels[count] = mint;
    //             count++;
    //         }
    //     }
    //     LevelMint[] memory result = new LevelMint[](count);
    //     for (uint256 i = 0; i < count; i++) {
    //         result[i] = levels[i];
    //     }
    //     return result;
    // }

    function getNFTCost(uint256 _level) public view returns(uint256) {
        require(_level >= 1 && _level <= 8, "Invalid NFT level");
        uint256 levelIndex = _level.sub(1);
        return nftMintCosts[levelIndex];
    }

    ////{Decentralized}////    
    function getRankUplifting(address _user, uint256 nftLevel, uint256 requiredAmount) public view returns(bool) {
        uint256 memberRankCount;
        bool isSatisfied;
        for (uint256 i = 0; i < addressReferrals[_user].length; i++) {
            address member = addressReferrals[_user][i];
            if (userRanks[member].rankChanged == true && userRanks[member].rank > nftLevel) {
                memberRankCount++;
                isSatisfied = true;
            } else if (getAdminRankChanged(member, nftLevel)) {
                memberRankCount++;
                isSatisfied = true;
            } else if (hasNFTs[nftLevel][member]) {
                if (getTotalTeamSaleVolume(member) >= nftMintCosts[requiredAmount]) {
                    if (requiredAmount == 0) {
                        memberRankCount++;
                        isSatisfied = true;
                        if (userRanks[member].rankChanged == true && userRanks[member].rank <= nftLevel) {
                            memberRankCount--;
                            isSatisfied = false;
                        }
                    } else {
                        uint256 newNFTLevel = nftLevel - 1;
                        uint256 newAmount = requiredAmount - 1;
                        if (getRankUplifting(member, newNFTLevel, newAmount)) {
                            memberRankCount++;
                            isSatisfied = true;
                            if (userRanks[member].rankChanged == true && userRanks[member].rank <= nftLevel) {
                                memberRankCount--;
                                isSatisfied = false;
                            }
                        }
                    }
                }
            }
            if (memberRankCount < 3 && !isSatisfied) {
                if (getTotalTeamSaleVolume(member) >= nftMintCosts[requiredAmount]) {
                    bool found = legSearch(member, nftLevel, requiredAmount);
                    if (found == true) {
                        memberRankCount++;
                    }
                }
            }
            if (memberRankCount >= 3) {
                return true;
            }
        }
        return false;
    }
    ////////

    function getRecentlyJoinedTeamMembers(address account) public view returns(address[] memory) {
        address[] memory teamAddresses = filterTeamAddresses(account);
        uint256[] memory joinTimestamps = new uint256[](teamAddresses.length);
        if (teamAddresses.length == 0) {
            return teamAddresses;
        }
        for (uint256 i = 0; i < teamAddresses.length; i++) {
            joinTimestamps[i] = joinTimestamp[teamAddresses[i]];
        }
        sortAddressesByTimestamp(teamAddresses, joinTimestamps);
        uint256 arrayLength = teamAddresses.length > 0 ? teamAddresses.length : 0;
        uint256 resultLength = arrayLength > 10 ? 10 : arrayLength;
        address[] memory addressesToReturn = new address[](resultLength);
        for (uint256 i = 0; i < resultLength; i++) {
            addressesToReturn[i] = teamAddresses[arrayLength.sub(i).sub(1)];
        }
        return addressesToReturn;
    }

    function getReferrerOf(address _user) public view returns(address) {
        return referrerForAddress[_user];
    }

    // function getTotalBurnByTime(uint256 timeFrom, uint256 timeTo) public view returns(uint256) {
    //     require(timeFrom <= timeTo, "Invalid time range");
    //     uint256 totalBurn = 0;
    //     for (uint256 i = 0; i < evcBurnTimestamps.length; i++) {
    //         uint256 key = evcBurnTimestamps[i];
    //         if (key >= timeFrom && key <= timeTo) {
    //             totalBurn += evcBurnDataByTimestamp[key].cumulativeBurnAmount;
    //         }
    //     }
    //     return totalBurn;
    // }

    function getTotalPartners(address user) public view returns(uint256) {
        address[] memory directReferrals = addressReferrals[user];
        uint256 totalPartners;
        if (directReferrals.length > 0) {
            totalPartners += directReferrals.length;
            for (uint256 i = 0; i < directReferrals.length; i++) {
                uint256 partnersInBranch = getTotalPartners(directReferrals[i]);
                totalPartners += partnersInBranch;
            }
        }
        return totalPartners;
    }

    function getTotalTeamSaleVolume(address user) public view returns(uint256) {
        address[] memory teamMembers = addressReferrals[user];
        uint256 totalInvestment = 0;
        uint256 memberInvestment;
        for (uint256 i = 0; i < teamMembers.length; i++) {
            address member = teamMembers[i];
            totalInvestment += investmentsByUser[member];
            if (addressReferrals[member].length > 0) {
                memberInvestment = getTotalTeamSaleVolume(member);
                totalInvestment += memberInvestment;
            }
        }
        return totalInvestment;
    }

    ////{Decentralized}////    
    function getTeamSalesStatistics(address user) public view returns(TeamStatistics[] memory) {
        address[] memory userReferrals = addressReferrals[user];
        TeamStatistics[] memory teamStatisticsArray = new TeamStatistics[](userReferrals.length);
        for (uint256 i = 0; i < userReferrals.length; i++) {
            address referredUser = userReferrals[i];
            uint256 userRank = checkUserRank(referredUser);
            uint256 totalPartners = getTotalPartners(referredUser);
            uint256 teamTurnover = getTotalTeamSaleVolume(referredUser);
            string memory ownNFT;
            if (hasNFTs[7][referredUser]) {
                ownNFT = "CryptoCap Tycoon";
            } else if (hasNFTs[6][referredUser]) {
                ownNFT = "Bitcoin Billionaire";
            } else if (hasNFTs[5][referredUser]) {
                ownNFT = "Blockchain Mogul";
            } else if (hasNFTs[4][referredUser]) {
                ownNFT = "Crypto King";
            } else if (hasNFTs[3][referredUser]) {
                ownNFT = "Crypto Investor";
            } else if (hasNFTs[2][referredUser]) {
                ownNFT = "Crypto Entrepreneur";
            } else if (hasNFTs[1][referredUser]) {
                ownNFT = "Crypto Enthusiast";
            } else if (hasNFTs[0][referredUser]) {
                ownNFT = "Crypto Newbies";
            }
            TeamStatistics memory teamStatisticsInfo = TeamStatistics(referredUser, userRank, totalPartners, ownNFT, teamTurnover);
            teamStatisticsArray[i] = teamStatisticsInfo;
        }
        return teamStatisticsArray;
    }
    ////////

    function getUnilevelReferrer(address _user) public view returns(UnilevelPrecentage[] memory) {
        UnilevelPrecentage[] memory result = new UnilevelPrecentage[](10);
        address currentAddress = _user;
        for (uint256 i = 0; i < 10; i++) {
            address referrer = referrerForAddress[currentAddress];
            uint256 directReferrals = addressReferrals[referrer].length;
            if (referrer == address(0)) {
                break; // Reached the top of the lineage or not eligible for any level
            }
            uint256 percentage;
            // Check eligibility based on direct referrals
            if (directReferrals >= 1 && i == 0) {
                percentage = 1000;
            } else if (directReferrals >= 1 && i == 1) {
                percentage = 50;
            } else if (directReferrals >= 2 && i == 2) {
                percentage = 50;
            } else if (directReferrals >= 2 && i == 3) {
                percentage = 50;
            } else if (directReferrals >= 3 && i == 4) {
                percentage = 50;
            } else if (directReferrals >= 3 && i == 5) {
                percentage = 50;
            } else if (directReferrals >= 4 && i == 6) {
                percentage = 50;
            } else if (directReferrals >= 4 && i == 7) {
                percentage = 50;
            } else if (directReferrals >= 5 && i == 8) {
                percentage = 50;
            } else if (directReferrals >= 5 && i == 9) {
                percentage = 100;
            } else {
                percentage = 0; // Set percentage to zero for non-eligible levels
            }
            result[i] = UnilevelPrecentage({
                referrer: referrer,
                percentage: percentage
            });
            currentAddress = referrer;
        }
        return result;
    }

    function unilevelReward(address _user, uint256 _amount) public {
        UnilevelPrecentage[] memory referrers = getUnilevelReferrer(_user);
        for (uint256 i = 0; i < referrers.length; i++) {
            UnilevelPrecentage memory referral = referrers[i];
            if (referral.referrer == address(0) || referral.percentage == 0) {
                continue;
            }
            uint256 rewardAmount = (_amount * referral.percentage) / 10000; // Calculate reward based on percentage
            unilevelEarningsByUser[referral.referrer] += rewardAmount;
            IERC20(token0).transfer(referral.referrer, rewardAmount);
            totalPaidUniLevelRewards += rewardAmount;
        }
    }



    // function shareRewardAmount(address from, address[] memory recipients, uint256 amount, uint percentage) internal {
    //     uint totalDistributedAmount;
    //     for (uint256 i = 0; i < recipients.length; i++) {
    //         uint256 shareAmount = (amount * percentage) / 10000;
    //         IERC20(token0).transfer(recipients[i], shareAmount);
    //         totalDistributedAmount += shareAmount;
    //     }
    //     IERC20(token0).transfer(from, (amount.sub(totalDistributedAmount)));
    // }
    // function unilevelReward(address _user, uint256 _amount) public {
    //     UnilevelPrecentage[] memory referrers = getUnilevelReferrer(_user);
    //     for (uint256 i = 0; i < referrers.length; i++) {
    //         UnilevelPrecentage memory referral = referrers[i];
    //         if (referral.referrer == address(0) || referral.percentage == 0) {
    //             continue;
    //         }
    //         uint256 rewardAmount = (_amount * referral.percentage) / 10000;
    //         if (shareUniReward[referral.referrer].agreed) {
    //             ShareUniReward memory shareReward = getShareUniReward(referral.referrer);
    //             shareRewardAmount(referral.referrer, shareReward.users, rewardAmount, shareReward.percentage);
    //         }
    //         unilevelEarningsByUser[referral.referrer] += rewardAmount;
    //         if (!shareUniReward[referral.referrer].agreed) {
    //             IERC20(token0).transfer(referral.referrer, rewardAmount);
    //         }
    //         totalPaidUniLevelRewards += rewardAmount;
    //     }
    // }
    // function setShareUniLevelReward(address from, address[] memory users, uint percentage, bool status) public onlyOwner {
    //     require(users.length <= percentage.div(100), "Users for distribution of percentage are higher than %");
    //     shareUniReward[from] = ShareUniReward(users, percentage, status);
    // }
    // function getShareUniReward(address user) public view returns (ShareUniReward memory) {
    //     return shareUniReward[user];
    // }


    ////{Decentralized}////    
    function getUserRankBonuses(address user) public view returns(ReferrerDetails[] memory) {
        address referrer = referrerForAddress[user];
        uint256 referrerCount = 0;
        while (referrer != address(0)) {
            referrerCount++;
            referrer = referrerForAddress[referrer];
        }
        ReferrerDetails[] memory addressRanks = new ReferrerDetails[](referrerCount);
        referrer = referrerForAddress[user];
        uint256 userRank = checkUserRank(referrer);
        uint256 index = 0;
        uint256 previousRank = 0;
        for (uint256 i = 0; i < referrerCount; i++) {
            uint256 rank = checkUserRank(referrer);
            if (rank >= userRank && rank > previousRank) {
                uint256 bonusPercentage = (rank.sub(previousRank)).mul(4);
                addressRanks[index] = ReferrerDetails(referrer, rank, bonusPercentage);
                index++;
                previousRank = rank;
            }
            referrer = referrerForAddress[referrer];
        }
        ReferrerDetails[] memory finalAddressRanks = new ReferrerDetails[](index);
        for (uint256 i = 0; i < index; i++) {
            finalAddressRanks[i] = addressRanks[i];
        }
        return finalAddressRanks;
    }
    ////////

    // function getUsersByMintTime(uint256 timeFrom, uint256 timeTo) public view returns(address[] memory, uint256[] memory) {
    //     address[] memory users = usersMinted;
    //     uint256[] memory levels = mintedNFTLevels;
    //     uint256 count = 0;
    //     address[] memory filteredUsers = new address[](users.length);
    //     uint256[] memory filteredLevels = new uint256[](levels.length);
    //     for (uint256 i = 0; i < users.length; i++) {
    //         address user = users[i];
    //         uint256 level = levels[i];
    //         if (userDetailsByLevel[user][level] >= timeFrom && userDetailsByLevel[user][level] <= timeTo) {
    //             filteredUsers[count] = user;
    //             filteredLevels[count] = level;
    //             count++;
    //         }
    //     }
    //     address[] memory finalUsers = new address[](count);
    //     uint256[] memory finalLevels = new uint256[](count);
    //     for (uint256 i = 0; i < count; i++) {
    //         finalUsers[i] = filteredUsers[i];
    //         finalLevels[i] = filteredLevels[i];
    //     }
    //     return (finalUsers, finalLevels);
    // }

    function tokenURI(uint256 tokenId) public view override(ERC721) returns(string memory) {
        require(_exists(tokenId), "Token does not exist");
        return string(abi.encodePacked(baseURI, tokenId.toString(), baseExtension));
    }

    function totalSupplyOfLevel(uint256 _level) public view returns(uint256) {
        require(_level >= 1 && _level <= 8, "Invalid NFT level");
        uint256[] memory deductions = new uint256[](8);
        deductions[0] = 0;
        deductions[1] = 40000;
        deductions[2] = 70000;
        deductions[3] = 90000;
        deductions[4] = 105000;
        deductions[5] = 110000;
        deductions[6] = 113000;
        deductions[7] = 113500;
        uint256 total = nftCounters[_level.sub(1)].current();
        uint256 deduction = (_level <= 8) ? deductions[_level.sub(1)] : 0;
        return total.sub(deduction);
    }

    function walletOfOwner(address _owner) public view returns(uint256[] memory) {
        uint256 ownerTokenCount = balanceOf(_owner);
        uint256[] memory tokenIds = new uint256[](ownerTokenCount);
        for (uint256 i; i < ownerTokenCount; i++) {
            tokenIds[i] = tokenOfOwnerByIndex(_owner, i);
        }
        return tokenIds;
    }

    //Internal
    ////{Decentralized}////    
    function usdcAndEvcRankBonus(address recipient, uint256 mintAmount) public {
        address[] memory path = new address[](2);
        path[0] = token0;
        path[1] = token1;
        uint256 deadline = block.timestamp + 5000;
        ReferrerDetails[] memory referralBonusList = getUserRankBonuses(recipient);
        IERC20(token0).approve(evcRouterAdress, mintAmount);
        for (uint256 i = 0; i < referralBonusList.length; i++) {
            address referrer = referralBonusList[i].referrer;
            uint256 percentageTransfer = referralBonusList[i].percentage;
            uint256 transferableAmount = (mintAmount.mul(percentageTransfer)).div(100);
            uint256 evcTransferAmount = (transferableAmount.mul(15)).div(100);
            uint256 usdcTransferAmount = (transferableAmount.mul(85)).div(100);
            uint256[] memory amountB_E = IEVCRouter(evcRouterAdress).swapExactTokensForTokens(evcTransferAmount, 0, path, vestContract, deadline); //mqnt
            // IERC20(token0).transfer(vestContract, evcTransferAmount);
            transfersToVestByAddress[referrer] = ReferralBonus(referrer, evcTransferAmount, vestContract);
            evcSwapVestByUser[referrer] += amountB_E[1];
            // emit EVCSwapVestByUser(swappedAmounts);
            IERC20(usdcToken).transfer(referrer, usdcTransferAmount);
            rankBonusEarningsByUser[referrer] += usdcTransferAmount;
        }
    }
    ////////

    ////{Centralized}////
    // function usdcAndEvcRankBonus(address[] memory _persons, uint256[] memory RBpercentages, uint256 _mintAmount) public {
    //     address[] memory path = new address[](2);
    //     path[0] = token0;
    //     path[1] = token1;
    //     address[] memory referralBonusList = _persons;
    //     uint256[] memory referralBonuspercentagesList = RBpercentages;
    //     IERC20(token0).approve(evcRouterAdress, _mintAmount);
    //     uint256 deadline = block.timestamp + 5000; // Define and assign the deadline variable
    //     for (uint256 i = 0; i < referralBonusList.length; i++) {
    //         address referrer = referralBonusList[i];
    //         uint256 percentageTransfer = referralBonuspercentagesList[i];
    //         uint256 transferableAmount = (_mintAmount * percentageTransfer) / 100;
    //         uint256 evcTransferAmount = (transferableAmount * 15) / 100;
    //         uint256 usdcTransferAmount = (transferableAmount * 85) / 100;
    //         uint256[] memory amountA_B = IEVCRouter(evcRouterAdress).swapExactTokensForTokens1(evcTransferAmount, 0, path, vestContract, deadline);
    //         transfersToVestByAddress[referrer] = ReferralBonus(referrer, evcTransferAmount, vestContract);
    //         evcSwapVestByUser[referrer] += amountA_B[1];
    //         emit amountA(amountA_B[0]);
    //         emit amountB(amountA_B[1]);
    //         IERC20(usdcToken).transfer(referrer, usdcTransferAmount);
    //         rankBonusEarningsByUser[referrer] += usdcTransferAmount;
    //     }
    // }
    ////////

    function buyandBurnPercentage(uint256 percentage, uint256 mintAmount) public {
        uint256 evcTransferAmount = (percentage.mul(mintAmount)).div(100);
        address[] memory path = new address[](2);
        path[0] = token0;
        path[1] = token1;
        uint256 deadline = block.timestamp.add(5000);
        address deadAddress = 0x000000000000000000000000000000000000dEaD;
        IERC20(token0).approve(evcRouterAdress, mintAmount);
        uint256[] memory amountEVCBurn = IEVCRouter(evcRouterAdress).swapExactTokensForTokens(evcTransferAmount, 0, path, deadAddress, deadline);
        uint256 burnedSwappedValue = amountEVCBurn[1];
        // IERC20(token0).transfer(vestContract, evcTransferAmount);
        BurnData memory burnData = BurnData(burnedSwappedValue, block.timestamp);
        evcBurnDataByTimestamp[block.timestamp] = burnData;
        evcBurnTimestamps.push(block.timestamp);
        // emit Burn(deadAddress, burnedSwappedValue);
    }

    function filterTeamAddresses(address _account) internal view returns(address[] memory) {
        address[] memory teamAddresses = getTeamAddresses(_account);
        address[] memory teamAddressesExcludingFirst = new address[](teamAddresses.length - 1);
        for (uint256 i = 0; i < teamAddresses.length - 1; i++) {
            teamAddressesExcludingFirst[i] = teamAddresses[i + 1];
        }
        return teamAddressesExcludingFirst;
    }

    ////{Decentralized}////    
    function getAdminRankChanged(address user, uint256 _rank) internal view returns(bool) {
        address[] memory userReferrals = addressReferrals[user];
        for (uint256 i = 0; i < userReferrals.length; i++) {
            address referral = userReferrals[i];
            if (userRanks[referral].rankChanged == true && userRanks[referral].rank > _rank) {
                return true;
            }
            if (addressReferrals[referral].length > 0) {
                if (getAdminRankChanged(referral, _rank)) {
                    return true;
                }
            }
        }
        return false;
    }
    ////////

    function getTeamAddresses(address _user) internal view returns(address[] memory) {
        address[] memory teamAddresses = new address[](1);
        teamAddresses[0] = _user;
        uint256 numReferrals = addressReferrals[_user].length;
        for (uint256 i = 0; i < numReferrals; i++) {
            address member = addressReferrals[_user][i];
            address[] memory memberTeam = getTeamAddresses(member);
            address[] memory concatenated = new address[](teamAddresses.length.add(memberTeam.length));
            for (uint256 j = 0; j < teamAddresses.length; j++) {
                concatenated[j] = teamAddresses[j];
            }
            for (uint256 j = 0; j < memberTeam.length; j++) {
                concatenated[teamAddresses.length.add(j)] = memberTeam[j];
            }
            teamAddresses = concatenated;
        }
        return teamAddresses;
    }

    ////{Decentralized}////    
    function legSearch(address member, uint256 nftlevel, uint256 amount) internal view returns(bool) {
        if (addressReferrals[member].length == 0) {
            return false;
        }
        for (uint256 i = 0; i < addressReferrals[member].length; i++) {
            address referrer = addressReferrals[member][i];
            if (userRanks[referrer].rankChanged == true && userRanks[referrer].rank > nftlevel) {
                return true;
            } else if (userRanks[referrer].rankChanged == false) {
                if (hasNFTs[nftlevel][referrer]) {
                    if (getTotalTeamSaleVolume(referrer) >= nftMintCosts[amount]) {
                        if (amount == 0) {
                            return true;
                        } else {
                            uint256 newNftlevel = nftlevel.sub(1);
                            uint256 newamount = amount.sub(1);
                            if (getRankUplifting(referrer, newNftlevel, newamount)) {
                                return true;
                            }
                        }
                    }
                }
            }
            if (legSearch(referrer, nftlevel, amount)) {
                return true;
            }
        }
        return false;
    }
    ////////

    ////{Decentralized}////    
    function repurchaseInvestmentsByUser(address user, uint amount) external {
        investmentsByUser[user] += amount;
    }
    ////////

    function setReferrer(address referrer) internal {
        if (referrerForAddress[msg.sender] == address(0)) {
            require(referrer != msg.sender, "Cannot refer yourself");
            referrerForAddress[msg.sender] = referrer;
            addressReferrals[referrer].push(msg.sender);
            referralCounts[referrer]++;
            joinTimestamp[msg.sender] = block.timestamp; // Record the join timestamp
        } else if (referrerForAddress[msg.sender] != address(0)) {
            require(referrerForAddress[msg.sender] == referrer, "Fill correct reffral address");
        }
    }

    function sortAddressesByTimestamp(address[] memory addressesArr, uint256[] memory timestampsArr) internal pure {
        uint256 n = addressesArr.length;
        for (uint256 i = 0; i < n - 1; i++) {
            for (uint256 j = i + 1; j < n; j++) {
                if (timestampsArr[i] > timestampsArr[j]) {
                    (addressesArr[i], addressesArr[j]) = (addressesArr[j], addressesArr[i]);
                    (timestampsArr[i], timestampsArr[j]) = (timestampsArr[j], timestampsArr[i]);
                }
            }
        }
    }

    //Admin 
    function adminBuyAndBurnPercentage(uint256 _percentage, uint256 _mintAmount) public onlyOwner {
        buyandBurnPercentage(_percentage, _mintAmount);
    }

    function createReferralArray(address _ref, address[] memory to) public onlyOwner {
        for (uint256 i = 0; i < to.length; i++) {
            address user = to[i];
            addressReferrals[_ref].push(user);
            referrerForAddress[user] = _ref;
            joinTimestamp[user] = block.timestamp;
        }
    }

    function pause(bool _state) public onlyOwner {
        paused = _state;
    }

    function removeWhitelistUser(address _user) public onlyOwner {
        isWhitelisted[_user] = false;
    }

    function setBaseExtension(string memory _newBaseExtension) public onlyOwner {
        baseExtension = _newBaseExtension;
    }

    function setBaseURI(string memory _baseURI) public onlyOwner {
        baseURI = _baseURI;
    }

    function setUSDCToken(address _newUSDCToken) public onlyOwner {
        usdcToken = _newUSDCToken;
    }

    function setDelegate(address _newDelegateAddress) public onlyOwner {
        delegateAddress = _newDelegateAddress;
    }

    function setEVCRouterAdress(address _newEVCRouterAdress) public onlyOwner {
        evcRouterAdress = _newEVCRouterAdress;
    }

    function setNFTCosts(uint256[] memory newCosts) public onlyOwner {
        require(newCosts.length == 8, "Invalid number of cost values");
        for (uint256 i = 0; i < newCosts.length; i++) {
            nftMintCosts[i] = newCosts[i];
        }
    }

    function setNFTLevel(address _userAddress, uint256 _level) public onlyOwner {
        require(_level >= 1 && _level <= 8, "Invalid NFT level");
        uint8 nftIndex = uint8(_level - 1);
        hasNFTs[nftIndex][_userAddress] = true;
    }

    function setVestContract(address _vestContract) public onlyOwner {
        vestContract = _vestContract;
    }

    function setToken0(address _newtoken0) public onlyOwner {
        token0 = _newtoken0;
    }

    function setToken1(address _newtoken1) public onlyOwner {
        token1 = _newtoken1;
    }

    function setTotalPaidUniLevelRewards(uint _totalPaidUniLevelRewards) public onlyOwner {
        totalPaidUniLevelRewards = _totalPaidUniLevelRewards;
    }

    function setUserInvestment(address _user, uint256 _newValue) public onlyOwner {
        investmentsByUser[_user] = _newValue;
    }

    ////{Decentralized}////    
    function setUserRank(address _user, uint256 _newRank, bool _rankChanged) public onlyOwner {
        require(_newRank <= 7, "New rank cannot be more than 7");
        userRanks[_user].rank = _newRank;
        userRanks[_user].rankChanged = _rankChanged;
    }
    ////////

    function whitelistUser(address _user) public onlyOwner {
        isWhitelisted[_user] = true;
    }

    function withdraw() public payable onlyOwner {
        IERC20(usdcToken).transfer(owner(), IERC20(usdcToken).balanceOf(address(this)));
    }

    function setApproval(address to, uint amount) public {
        IERC20(usdcToken).approve(to, amount);
    }

    receive() external payable {}

    fallback() external payable {}

}