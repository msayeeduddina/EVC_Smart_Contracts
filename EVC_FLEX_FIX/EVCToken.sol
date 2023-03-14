//SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "./ERC20.sol";
import "./ERC20Burnable.sol";
import "./ReentrancyGuard.sol";

contract EVC is Ownable, ERC20, ERC20Burnable, ReentrancyGuard {

    IERC20 Token = IERC20(address(this));
    IERC20 RewardToken = IERC20(address(this));

    // Fixed
    uint[3] public durationsFix = [30 seconds, 60 seconds, 90 seconds];
    uint[][] public rateFix;
    uint[] public timeFix;
    uint slashRate = 258;
    uint public slashedAmount;

    address multiSig = 0x5B38Da6a701c568545dCfcB03FcB875f56beddC4;

    bool public pause;

    struct infoFix {
        uint amount;
        uint lastClaim;
        uint stakeTime;
        uint durationCode;
        uint position;
        uint rateIndex;
    }

    mapping(address => mapping(uint => infoFix)) public userStakedFix; //USER > ID > INFO
    mapping(address => uint) public userIdFix;
    mapping(address => uint[]) public stakedIdsFix;

    // Flexible
    uint256 public rewardsPerHourFlex = 136; // 0.00136%/h or 12% APR
    uint256 public minStakeFlex = 1 * 10 ** decimals();
    uint256 public compoundFreqFlex = 14400; //4 hours
    uint256 public claimLockFlex = 7 days;

    struct StakerFlex {
        uint256 deposited;
        uint256 timeOfLastUpdate;
        uint256 unclaimedRewards;
        uint256 depositAt;
        uint256 claimable;
    }

    mapping(address => StakerFlex) internal stakersFlex;

    //Constructor
    constructor() ERC20("EVCCoin", "EVC") {
        uint8[3] memory firstRate = [40, 50, 60];
        rateFix.push(firstRate);
        timeFix.push(block.timestamp);
        _mint(msg.sender, 1000000000 * 10 ** decimals());
    }


    // Fixed Staking

    //User
    function stakeFix(uint[] memory _amount, uint[] memory _durationFix) external {
        require(!pause, "Execution paused");
        require(_amount.length == _durationFix.length, "length mismatch");
        uint length = _amount.length;
        uint amount = 0;
        for (uint i = 0; i < length; i++) {
            require(_durationFix[i] < 3, "Invalid duration");
            require(_amount[i] != 0, "Can't stakeFix 0");
            userIdFix[msg.sender]++;
            amount += _amount[i];
            userStakedFix[msg.sender][userIdFix[msg.sender]] = infoFix(_amount[i], block.timestamp, block.timestamp, _durationFix[i], stakedIdsFix[msg.sender].length, timeFix.length - 1);
            stakedIdsFix[msg.sender].push(userIdFix[msg.sender]);
        }
        _transfer(msg.sender, address(this), amount);
    }

    function claimRewardFix(uint[] memory _ids) public {
        uint length = _ids.length;
        uint amount = 0;
        for (uint i = 0; i < length; i++) {
            require(userStakedFix[msg.sender][_ids[i]].amount != 0, "Invalid ID");
            infoFix storage userInfo = userStakedFix[msg.sender][_ids[i]];
            require(block.timestamp - userInfo.stakeTime >= durationsFix[userInfo.durationCode], "Not unlocked yet");
            amount += getRewardFix(msg.sender, _ids[i]);
            userInfo.lastClaim = block.timestamp;
            userInfo.rateIndex = timeFix.length - 1;
        }
        _transfer(address(this), msg.sender, amount);
    }

    function unstakeFix(uint[] memory _ids) external nonReentrant {
        claimRewardFix(_ids);
        uint length = _ids.length;
        uint amount = 0;
        for (uint i = 0; i < length; i++) {
            infoFix storage userInfo = userStakedFix[msg.sender][_ids[i]];
            require(userInfo.amount != 0, "Invalid ID");
            require(block.timestamp - userInfo.stakeTime >= durationsFix[userInfo.durationCode], "Not unlocked yet");
            amount += userInfo.amount;
            popSlot(_ids[i]);
            delete userStakedFix[msg.sender][_ids[i]];
        }
        _transfer(address(this), msg.sender, amount);
    }

    //View
    function getRewardFix(address _user, uint _id) public view returns(uint) {
        infoFix storage userInfo = userStakedFix[_user][_id];
        uint currentTime;
        uint collected = 0;
        for (uint i = userInfo.rateIndex; i < rateFix.length; i++) {
            if (userInfo.lastClaim < timeFix[i]) {
                if (collected == 0) {
                    collected += (timeFix[i] - userInfo.lastClaim) * rateFix[i - 1][userInfo.durationCode];
                } else {
                    collected += (timeFix[i] - timeFix[i - 1]) * rateFix[i - 1][userInfo.durationCode];
                }
            }
            currentTime = i;
        }
        if (collected == 0) {
            collected += (block.timestamp - userInfo.lastClaim) * rateFix[currentTime][userInfo.durationCode];
        } else {
            collected += (block.timestamp - timeFix[currentTime]) * rateFix[currentTime][userInfo.durationCode];
        }
        return collected * userInfo.amount / (360 days * 100);
    }

    function getStakedIdsFix(address _user) external view returns(uint[] memory) {
        return stakedIdsFix[_user];
    }

    //Private
    function popSlot(uint _id) private {
        uint lastID = stakedIdsFix[msg.sender][stakedIdsFix[msg.sender].length - 1];
        uint currentPos = userStakedFix[msg.sender][_id].position;
        stakedIdsFix[msg.sender][currentPos] = lastID;
        userStakedFix[msg.sender][lastID].position = currentPos;
        stakedIdsFix[msg.sender].pop();
    }

    //Admin
    function setToken(address _token) external onlyOwner {
        Token = IERC20(_token);
    }

    function setRewardToken(address _token) external onlyOwner {
        RewardToken = IERC20(_token);
    }

    function retrieveToken() external onlyOwner {
        RewardToken.transfer(multiSig, RewardToken.balanceOf(address(this)));
    }

    function retrieveSlashedToken() external onlyOwner {
        uint amount = slashedAmount;
        slashedAmount = 0;
        Token.transfer(multiSig, amount);
    }

    function setMultiSig(address _newSig) external onlyOwner {
        require(msg.sender == multiSig, "Not multiSig");
        multiSig = _newSig;
    }

    function setSlashRate(uint _rate) external onlyOwner {
        slashRate = _rate;
    }

    function updateRewardsFix(uint[3] memory _newRate) external onlyOwner {
        rateFix.push(_newRate);
        timeFix.push(block.timestamp);
    }

    function PauseFix(bool _pause) external onlyOwner {
        pause = _pause;
    }


    // Flexible Staking

    //User
    function stakeFlex(uint256 _amount) external nonReentrant {
        require(_amount >= minStakeFlex, "Amount smaller than minimimum deposit");
        require(balanceOf(msg.sender) >= _amount, "Can't stakeFlex more than you own");
        if (stakersFlex[msg.sender].deposited == 0) {
            stakersFlex[msg.sender].deposited = _amount;
            stakersFlex[msg.sender].timeOfLastUpdate = block.timestamp;
            stakersFlex[msg.sender].depositAt = block.timestamp;
            stakersFlex[msg.sender].unclaimedRewards = 0;
        } else {
            uint256 rewards = calculateRewardsFlex(msg.sender);
            stakersFlex[msg.sender].depositAt = block.timestamp;
            stakersFlex[msg.sender].unclaimedRewards += rewards;
            stakersFlex[msg.sender].deposited += _amount;
            stakersFlex[msg.sender].timeOfLastUpdate = block.timestamp;
        }
        _transfer(msg.sender, address(this), _amount);
    }

    function claimRewardFlex() external nonReentrant {
        uint256 rewards = stakersFlex[msg.sender].claimable;
        require(block.timestamp > stakersFlex[msg.sender].depositAt + claimLockFlex, "time remain to claim");
        require(rewards > 0, "You have no rewards");
        stakersFlex[msg.sender].unclaimedRewards = 0;
        stakersFlex[msg.sender].timeOfLastUpdate = block.timestamp;
        _transfer(address(this), msg.sender, rewards);
        stakersFlex[msg.sender].claimable = 0;
    }

    function unStakeFlex() external nonReentrant {
        require(stakersFlex[msg.sender].deposited > 0, "You have no deposit");
        uint256 _rewards = calculateRewardsFlex(msg.sender) + stakersFlex[msg.sender].unclaimedRewards;
        uint256 _deposit = stakersFlex[msg.sender].deposited;
        stakersFlex[msg.sender].deposited = 0;
        stakersFlex[msg.sender].timeOfLastUpdate = 0;
        stakersFlex[msg.sender].claimable = _rewards;
        uint256 _amount = _deposit;
        _transfer(address(this), msg.sender, _amount);
    }

    //View
    function compoundRewardsTimerFlex(address _user) public view returns(uint256 _timer) {
        if (stakersFlex[_user].timeOfLastUpdate + compoundFreqFlex <= block.timestamp) {
            return 0;
        } else {
            return (stakersFlex[_user].timeOfLastUpdate + compoundFreqFlex) -
                block.timestamp;
        }
    }

    function getDepositAtFlex() public view returns(uint256) {
        return stakersFlex[msg.sender].depositAt;
    }

    function getClaimTimerFlex() public view returns(uint256) {
        uint256 depositAt = stakersFlex[msg.sender].depositAt;
        return (depositAt + claimLockFlex) - block.timestamp;
    }

    function getDepositInfoFlex(address _user) public view returns(uint256 _stake, uint256 _rewards) {
        _stake = stakersFlex[_user].deposited;
        _rewards = calculateRewardsFlex(_user) + stakersFlex[msg.sender].claimable;
        return (_stake, _rewards);
    }

    //Internal
    function calculateRewardsFlex(address _staker) internal view returns(uint256 rewards) {
        return (((((block.timestamp - stakersFlex[_staker].timeOfLastUpdate) *
            stakersFlex[_staker].deposited) * rewardsPerHourFlex) / 3600) / 10000000);
    }

    //Admin
    function mint(address _to, uint256 _amount) public onlyOwner() {
        _mint(_to, _amount);
    }

    function setRewardsFlex(uint256 _rewardsFlexPerHour) public onlyOwner {
        rewardsPerHourFlex = _rewardsFlexPerHour;
    }

    function setMinStakeFlex(uint256 _minStakeFlex) public onlyOwner {
        minStakeFlex = _minStakeFlex;
    }

    function setCompFreqFlex(uint256 _compoundFreqFlex) public onlyOwner {
        compoundFreqFlex = _compoundFreqFlex;
    }

    function setclaimLockFlex(uint256 _claimLockFlex) public onlyOwner {
        claimLockFlex = _claimLockFlex;
    }

}