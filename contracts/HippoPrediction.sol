// SPDX-License-Identifier: MIT
pragma solidity 0.8.0;

import '@openzeppelin/contracts/utils/Context.sol';
import '@openzeppelin/contracts/access/Ownable.sol';
import '@openzeppelin/contracts/security/ReentrancyGuard.sol';
import '@openzeppelin/contracts/token/ERC20/IERC20.sol';
import '@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol';

import "@chainlink/contracts/src/v0.8/VRFConsumerBase.sol";


interface IRandomNumberConsumer {
    function getRandom(uint256 lotteryId) external;
}

contract RandomNumberConsumer is VRFConsumerBase, Ownable {
    
    bytes32 internal keyHash;
    uint256 internal fee;

    mapping (uint => uint) public randomNumber;
    mapping (bytes32 => uint) public requestIds;
    IRaffle public raffle;
    uint256 public most_recent_random;

    event SetRaffleAddress(address _raffleAddress);
    event RandomFullfilled(bytes32 requestId, uint256 randomness);
    
    constructor(address _raffleAddress) 
        VRFConsumerBase(
            0x8C7382F9D8f56b33781fE506E897a4F1e2d17255, // VRF Coordinator
            0x326C977E6efc84E512bB9C30f76E30c160eD06FB  // LINK Token
        )
    {
        keyHash = 0x6e75b569a01ef56d18cab6a8e71e6600d6ce853834d4a5748b720d06f878b3a4;
        fee = 0.0001 * 10 ** 18;
        raffle = IRaffle(_raffleAddress);
    }

    function setRaffleAddress(address _raffleAddress) external onlyOwner {
        raffle = IRaffle(_raffleAddress);

        emit SetRaffleAddress(_raffleAddress);
    }
    
    function getRandom(uint256 lotteryId) external {
        require(LINK.balanceOf(address(this)) > fee, "Not enough LINK - fill contract with faucet");
        bytes32 _requestId = requestRandomness(keyHash, fee);
        requestIds[_requestId] = lotteryId;
    }

    function fulfillRandomness(bytes32 requestId, uint256 randomness) internal override {
        require(msg.sender == address(0x8C7382F9D8f56b33781fE506E897a4F1e2d17255), "Fulillment only permitted by Coordinator");
        most_recent_random = randomness;
        uint lotteryId = requestIds[requestId];
        randomNumber[lotteryId] = randomness;
        raffle.fulfill_random(randomness);

        emit RandomFullfilled(requestId, randomness);
    }

    //withdraw function to avoid locking your token in the contract
    function recoverToken(address _token, uint256 _amount, address receiver) external onlyOwner {
        IERC20(_token).transfer(receiver, _amount);
    }
}

interface IRaffle {
    function fulfill_random(uint) external;
    function addUserTicket(address _userAddress, uint256 ticketAmount) external;
    function addBalance() external payable;
}

contract Raffle is Ownable, ReentrancyGuard, IRaffle {

    IRandomNumberConsumer public randomOracle;

    uint256 public minRoundDuration; // min interval in seconds between two raffle rounds
    uint256 public currentRound; // current round for raffle round
    uint256 public ticketMultiplier; //this is the global ticket multiplier that will effect all tickets received from other contracts

    uint256 public rewardTicketAmountForRaffleComplete = 10;

    struct Round {
        address[] entrants; //array of all entrants, winner will be picked by random index
        uint256 amount;  //total balance of round to send to the winner
        uint256 ticketCount; //total ticket count of all participated users
        uint256 startTimestamp; 
        uint256 endTimestamp; //0 if not complete yet
        uint256 winnerIndex; //random index of entrants[] to get winner
        address winner; //address of winner to let them claim. this is 0 if no winner yet
        bool claimed; //default false
    }

    mapping(uint256 =>  mapping(address => uint256)) public ledger; //keeps user ticket count per round
    mapping(address => uint256[]) public userRounds; //keeps round numbers user participated in
    mapping(uint256 => Round) public rounds; //keeps all rounds data
    mapping(address => bool) public addressesAllowedToAddTicket; //keeps other contract addresses that can interact with this contract

    event AddTicket(address indexed user, uint256 ticketAmount, uint256 indexed round);
    event AddBalance(uint256 amount, uint256 indexed round);
    event RoundComplete(address indexed user, uint256 indexed round, uint256 randomness);
    event ClaimRaffle(address indexed user, uint256 amount, uint256 indexed round);
    event SetVRFAddress(address _vrfAddress, uint256 indexed round);
    event AddAllowedAddress(address _allowedAddress, uint256 indexed round);
    event RemoveAllowedAddress(address _allowedAddress, uint256 indexed round);
    event SetTicketMultiplier(uint256 _ticketMultiplier, uint256 indexed round);
    event SetMinRoundDuration(uint256 _minRoundDuration, uint256 indexed round);

    modifier onlyAllowedContract() {
        require(addressesAllowedToAddTicket[msg.sender], "You dont have the permission to add ticket");
        _;
    }

    constructor(uint256 _minRoundDuration) {
        minRoundDuration = _minRoundDuration;
        ticketMultiplier = 1; 
        _startRound();
    }

    function setVRFAddress(address _vrfAddress) external onlyOwner {
        randomOracle = IRandomNumberConsumer(_vrfAddress);

        emit SetVRFAddress(_vrfAddress, currentRound);
    }

    function setRewardTicketAmountForRaffleComplete(uint256 _rewardTicketAmountForRaffleComplete) external onlyOwner {
        rewardTicketAmountForRaffleComplete = _rewardTicketAmountForRaffleComplete;
    }

    function pickWinner() external {
        require(block.timestamp >= rounds[currentRound-1].endTimestamp + minRoundDuration, "raffle cant be completed yet.");

        randomOracle.getRandom(currentRound);
        
        //start new round, so new tickets enter correctly before random is fulfilled
        _startRound();

        //give caller reward tickets
        _addUserTicket(msg.sender, rewardTicketAmountForRaffleComplete);
    }

    function _startRound() internal {
        currentRound = currentRound + 1;
        rounds[currentRound].startTimestamp = block.timestamp;
    }

    function fulfill_random(uint256 randomness) external override {
        require(randomness > 0, "random-not-found");
        require(msg.sender == address(randomOracle), "only the oracle can fulfill");

        //we get the previous round because a new round was started on pickWinner
        Round storage round = rounds[currentRound-1];
        round.endTimestamp = block.timestamp;

        uint256 _winnerIndex = randomness % round.entrants.length;
        round.winnerIndex = _winnerIndex;
        round.winner = round.entrants[_winnerIndex];

        emit RoundComplete(round.winner, currentRound-1, randomness);
    }

    function claimWinning(uint256 roundNo) external nonReentrant {
        Round storage round = rounds[roundNo];
        require(round.winner == msg.sender, "only the winner of this round can claim");
        require(!round.claimed, "this round was already claimed");

        round.claimed = true;
        _safeTransfer(address(msg.sender), round.amount);

        emit ClaimRaffle(msg.sender, round.amount, roundNo);
    }

    function _safeTransfer(address to, uint256 value) internal {
        (bool success, ) = to.call{value: value}("");
        require(success, "TransferHelper: TRANSFER_FAILED");
    }

    function _addUserTicket(address _userAddress, uint256 ticketAmount) internal {
        //dont implement actions if ticketAmount is 0
        //dont revert as it might prevent betting or other actions on other contracts
        if(ticketAmount > 0){
            Round storage round = rounds[currentRound];
            uint256 ticketsToAdd = ticketAmount  * ticketMultiplier;
            round.ticketCount += ticketsToAdd;
            ledger[currentRound][_userAddress] += ticketsToAdd;
            userRounds[_userAddress].push(currentRound);

            for(uint256 i = 0; i < ticketsToAdd; i++){
                round.entrants.push(_userAddress);
            }

            emit AddTicket(_userAddress, ticketAmount, currentRound);
        }
    }

    function addUserTicket(address _userAddress, uint256 ticketAmount) external override onlyAllowedContract {
        _addUserTicket(_userAddress, ticketAmount);
    }

    function addBalance() external payable override onlyAllowedContract {
        rounds[currentRound].amount += msg.value;

        emit AddBalance(msg.value, currentRound);
    }

    function addAllowedAddress(address _allowedAddress) external onlyOwner {
        require(_allowedAddress != address(0), 'cant add address 0');
        addressesAllowedToAddTicket[_allowedAddress] = true;

        emit AddAllowedAddress(_allowedAddress, currentRound);
    }

    function removeAllowedAddress(address _allowedAddress) external onlyOwner {
        require(_allowedAddress != address(0), 'cant remove address 0');
        addressesAllowedToAddTicket[_allowedAddress] = false;

        emit RemoveAllowedAddress(_allowedAddress, currentRound);
    }

    function setMinRoundDuration(uint256 _minRoundDuration) external onlyOwner {
        minRoundDuration = _minRoundDuration;

        emit SetMinRoundDuration(_minRoundDuration, currentRound);
    }

    function setTicketMultiplier(uint256 _ticketMultiplier) external onlyOwner {
        ticketMultiplier = _ticketMultiplier;

        emit SetTicketMultiplier(_ticketMultiplier, currentRound);
    }
}

//chainlink oracle interface
interface AggregatorV3Interface {
    function decimals() external view returns (uint8);
    function description() external view returns (string memory);
    function version() external view returns (uint256);
    function getRoundData(uint80 _roundId) external view returns (
        uint80 roundId, int256 answer, uint256 startedAt, uint256 updatedAt, uint80 answeredInRound);
    function latestRoundData() external view returns (
        uint80 roundId, int256 answer, uint256 startedAt, uint256 updatedAt,uint80 answeredInRound);
}

interface IReference {
    function hasReferrer(address user) external view returns (bool);
    function setReferrer(address referrer) external;
    function getReferrer(address user) external view returns (address);
}

contract Reference is IReference {
    mapping(address => address) public userReferrer; 
    mapping(address => bool) public userExistence;

    event EnableReferenceSystem(address indexed user);
    event SetReferrer(address indexed user, address indexed referrer);

    function enableAddress() external {
        require(!userExistence[msg.sender], "This address is already enabled");
        userExistence[msg.sender] = true;

        emit EnableReferenceSystem(msg.sender);
    }

    function setReferrer(address referrer) override external {
        require(userReferrer[msg.sender] == address(0), "You already have a referrer.");
        require(msg.sender != referrer, "You can not refer your own address.");
        require(userExistence[referrer], "The referrer address is not in the system.");
        userReferrer[msg.sender] = referrer;

        emit SetReferrer(msg.sender, referrer);
    }

    function hasReferrer(address user) override external view virtual returns (bool) {
        return userReferrer[user] != address(0);
    }

    function getReferrer(address user) override external view returns (address) {
        return userReferrer[user];
    }
}

contract HippoPrediction is Ownable, ReentrancyGuard {
    using SafeERC20 for IERC20;

    //raffle variables
    IRaffle public raffle;
    uint256 public raffleTicketNormalizer = 10000000000000000;
    uint256 public raffleLogMultiplier = 15; //times 10
    uint256 public rewardTicketAmountForExecuteRound = 10;
    uint256 public rewardTicketAmountForCompleteVoting = 10;
    //------

    address public adminAddress; // address of the admin

    uint32 public intervalSeconds; // interval in seconds between two prediction rounds

    uint256 public minBetAmount; // minimum betting amount (denominated in wei)
    uint256 public treasuryFee; // treasury rate x10
    uint256 public treasuryAmount; // treasury amount that was not claimed

    uint256 public raffleRate; // percent of treasury fee that will be sent to the raffle contract

    uint256 public currentEpoch; // current epoch for prediction round

    uint256 public constant MAX_TREASURY_FEE = 100; // 10%

    mapping(uint256 => mapping(address => BetInfo)) public ledger;
    mapping(uint256 => Round) public rounds;
    mapping(uint256 => Timestamps) public timestamps;
    mapping(address => uint256[]) public userRounds;

    //reference variables
    IReference public referenceSystem;
    uint256 public referrerBonus;
    uint256 public refereeBonus;
    mapping(address => uint256) public referrerBonuses; //keep referrer bonuses in a mapping, so they can claim total amount themselves
    //----------------

    //voting variables
    mapping(address => bool) public oracleExistence;
    address public selectedOracle;
    address public maxVotedOracle;
    uint256 public latestOracleUpdateTimestamp;
    uint256 public oracleVotingPeriod = 604800; //1 week in seconds
    uint256 public maxOracleVote;
    uint256 public currentOracleVoteRound;
    mapping(uint256 => mapping(address => bool)) public userVoteRounds; //[roundNo][userAddress]
    mapping(uint256 => mapping(address => uint256)) public oracleVotes; //[roundNo][oracleAddress]
    //----------------

    enum Position {
        Bull,
        Bear,
        Noresult
    }

    struct Round {
        int256 lockPrice;
        int256 closePrice;
        uint256 totalAmount;
        uint256 bullAmount;
        uint256 bearAmount;
        uint256 rewardBaseCalAmount;
        uint256 rewardAmount;
        uint256 bullBonusAmount;
        uint256 bearBonusAmount;
        uint80 lockOracleId;
        uint80 closeOracleId;
        address oracleAddress;
        bool oracleCalled;
        bool cancelled;
    }

    struct Timestamps {
        uint32 startTimestamp;
        uint32 lockTimestamp;
        uint32 closeTimestamp;
    }

    struct BetInfo {
        Position position;
        uint256 amount;
        uint256 refereeAmount;
        uint256 referrerAmount;
        bool claimed; // default false
    }

    event SetReferenceAddress(address referenceSystem, uint256 indexed epoch);
    event SetReferenceBonuses(uint256 referrerBonus, uint256 refereeBonus, uint256 indexed epoch);
    event ClaimReferrerBonus(address indexed sender, uint256 reward, uint256 indexed epoch);

    event AddOracle(address oracleAddress, uint256 indexed epoch);
    event RemoveOracle(address removedOracle, uint256 indexed epoch);
    event SetOraclesList(uint256 indexed epoch);
    event EmergencySetNewOracle(address oracle, uint256 indexed epoch);
    event CompleteOracleVoting(address oracle, uint256 maxOracleVote, uint256 indexed epoch);
    event OracleVote(address indexed sender, address oracle, uint256 indexed epoch);

    event NewBet(address indexed sender, uint256 indexed epoch, uint256 amount, uint8 position);
    event Claim(address indexed sender, uint256 indexed epoch, uint256 amount);
    event EndRound(uint256 indexed epoch, uint256 indexed roundId, int256 price);
    event LockRound(uint256 indexed epoch, uint256 indexed roundId, int256 price);

    event NewAdminAddress(address admin);
    event NewIntervalSeconds(uint32 intervalSeconds);
    event NewMinBetAmount(uint256 indexed epoch, uint256 minBetAmount);
    event NewTreasuryFee(uint256 indexed epoch, uint256 treasuryFee);
    event NewOracle(address oracle);
    event SetOracleVotingPeriod(uint256 votingPeriod, uint256 indexed epoch);

    event RewardsCalculated(uint256 indexed epoch, uint8 roundResultPosition, uint256 rewardBaseCalAmount, uint256 rewardAmount, uint256 treasuryAmount);

    event StartRound(uint256 indexed epoch);
    event CancelRound(uint256 indexed epoch);
    event TokenRecovery(address indexed token, uint256 amount);
    event TreasuryClaim(uint256 amount);

    event ReferrerBonus(address indexed user, address indexed referrer, uint256 amount, uint256 indexed currentEpoch);

    modifier onlyAdmin() {
        require(msg.sender == adminAddress, "Not admin");
        _;
    }

    modifier notContract() {
        require(!_isContract(msg.sender), "Contract not allowed");
        require(msg.sender == tx.origin, "Proxy contract not allowed");
        _;
    }

    constructor(
        address[] memory _oraclesList,
        uint32 _intervalSeconds,
        uint256 _minBetAmount,
        uint256 _treasuryFee,
        uint256 _raffleRate,
        uint256 _referrerBonus,
        uint256 _refereeBonus,
        address _referenceSystem
    ) {
        require(_treasuryFee <= MAX_TREASURY_FEE, "Treasury fee too high");
        require(_raffleRate + _referrerBonus + _refereeBonus <= 100, "cant be higher than 100%");
        require(_oraclesList.length > 0, "Oracles List is empty");

        selectedOracle = _oraclesList[0];
        for (uint256 i = 0; i < _oraclesList.length; i++) { 
            oracleExistence[_oraclesList[i]] = true;       
        }

        adminAddress = msg.sender;
        intervalSeconds = _intervalSeconds;
        minBetAmount = _minBetAmount;
        treasuryFee = _treasuryFee;
        raffleRate = _raffleRate;

        rounds[0].cancelled = true;
        currentEpoch = 1;
        _startRound(currentEpoch);

        referenceSystem = IReference(_referenceSystem);
        referrerBonus = _referrerBonus;
        refereeBonus = _refereeBonus;
    }

    //------------------------
    //REFERENCE SYSTEM FUNCTIONS
    function setReferenceAddress(address _referenceSystem) external onlyAdmin {
        referenceSystem = IReference(_referenceSystem);

        emit SetReferenceAddress(_referenceSystem, currentEpoch);
    }

    function setReferenceBonuses(uint256 _referrerBonus, uint256 _refereeBonus) external onlyAdmin {
        require(raffleRate + _referrerBonus + _refereeBonus <= 100, "cant be higher than 100%");
        referrerBonus = _referrerBonus;
        refereeBonus = _refereeBonus;

        emit SetReferenceBonuses(referrerBonus, refereeBonus, currentEpoch);
    }

    function claimReferrerBonus() external nonReentrant onlyOwner {
        require(referrerBonuses[msg.sender] > 0, "user has no referrer bonuses");
        uint reward = referrerBonuses[msg.sender];
        referrerBonuses[msg.sender] = 0;
        _safeTransfer(address(msg.sender), reward);

        emit ClaimReferrerBonus(msg.sender, reward, currentEpoch);
    }
    //------------------------

    //------------------------
    //ORACLE VOTING FUNCTIONS

    function addOracle(address[] memory _oraclesList) external onlyAdmin {
        for (uint256 i = 0; i < _oraclesList.length; i++) { 
            oracleExistence[_oraclesList[i]] = true;       
            // Dummy check to make sure the interface implements this function properly
            AggregatorV3Interface(_oraclesList[i]).latestRoundData();

            emit AddOracle(_oraclesList[i], currentOracleVoteRound);
        }
    }

    function removeOracle(address[] memory _oraclesList) external onlyAdmin {
        for (uint256 i = 0; i < _oraclesList.length; i++) { 
            oracleExistence[_oraclesList[i]] = false;       

            emit RemoveOracle(_oraclesList[i], currentOracleVoteRound);
        }
    }

    function setOracleVotingPeriod(uint256 _votingPeriod) external onlyAdmin {
        oracleVotingPeriod = _votingPeriod;

        emit SetOracleVotingPeriod(_votingPeriod, currentOracleVoteRound);
    }

    //once the voting period is over, anyonce can call this function and complete the voting
    //this will set the next round to start with the new oracle
    //live round that was locked with old oracle will still get its ending price from the previous oracle
    function completeOracleVoting() external {
        require(block.timestamp >= latestOracleUpdateTimestamp + oracleVotingPeriod, "Voting is not over yet");

        selectedOracle = maxVotedOracle;
        latestOracleUpdateTimestamp = block.timestamp;
        maxOracleVote = 0;
        currentOracleVoteRound = currentOracleVoteRound + 1;

        //give reward to the caller
        raffle.addUserTicket(msg.sender, rewardTicketAmountForCompleteVoting);

        emit CompleteOracleVoting(selectedOracle, maxOracleVote, currentOracleVoteRound);
    }

    //community can vote for the new oracle. every user can vote once
    function voteForNewOracle(address _oracleAddress) external {
        require(!userVoteRounds[currentOracleVoteRound][msg.sender], "you have already voted");
        require(oracleExistence[_oracleAddress], "oracle is not available");
        
        userVoteRounds[currentOracleVoteRound][msg.sender] = true;
        oracleVotes[currentOracleVoteRound][_oracleAddress]++;
        if(oracleVotes[currentOracleVoteRound][_oracleAddress] > maxOracleVote){
             maxOracleVote = oracleVotes[currentOracleVoteRound][_oracleAddress];
             maxVotedOracle = _oracleAddress;
        }

        emit OracleVote(msg.sender, _oracleAddress, currentOracleVoteRound);
    }
    //------------------------
    //------------------------

    function setRaffleAddress(address _raffleAddress) external onlyAdmin {
        raffle = IRaffle(_raffleAddress);
    }

    function setRaffleRate(uint256 _raffleRate) external onlyAdmin {
        require(_raffleRate + referrerBonus + refereeBonus <= 100, "cant be higher than 100%");
        raffleRate = _raffleRate;
    }

    function setRaffleTicketNormalizer(uint256 _raffleTicketNormalizer) external onlyAdmin {
        raffleTicketNormalizer = _raffleTicketNormalizer;
    }

    function setRaffleLogMultiplier(uint256 _raffleLogMultiplier) external onlyAdmin {
        raffleLogMultiplier = _raffleLogMultiplier;
    }

    function setRewardTicketAmountForExecuteRound(uint256 _rewardTicketAmountForExecuteRound) external onlyAdmin {
        rewardTicketAmountForExecuteRound = _rewardTicketAmountForExecuteRound;
    }

    function setRewardTicketAmountForCompleteVoting(uint256 _rewardTicketAmountForCompleteVoting) external onlyAdmin {
        rewardTicketAmountForCompleteVoting = _rewardTicketAmountForCompleteVoting;
    }

    function _addUserTicket(address _userAddress, uint256 _amount) internal {
        //add user tickets to the raffle system
        //log2 function is used to have a higher bonus for simply betting on a round
        //to incentive betting on multiple rounds instead of a single round
        uint256 ticketAmount = (raffleLogMultiplier * log2x(_amount / raffleTicketNormalizer) / 10) + 1;
        raffle.addUserTicket(_userAddress, ticketAmount);
    }

    function log2x(uint x) public pure returns (uint y){
        assembly {
                let arg := x
                x := sub(x,1)
                x := or(x, div(x, 0x02))
                x := or(x, div(x, 0x04))
                x := or(x, div(x, 0x10))
                x := or(x, div(x, 0x100))
                x := or(x, div(x, 0x10000))
                x := or(x, div(x, 0x100000000))
                x := or(x, div(x, 0x10000000000000000))
                x := or(x, div(x, 0x100000000000000000000000000000000))
                x := add(x, 1)
                let m := mload(0x40)
                mstore(m,           0xf8f9cbfae6cc78fbefe7cdc3a1793dfcf4f0e8bbd8cec470b6a28a7a5a3e1efd)
                mstore(add(m,0x20), 0xf5ecf1b3e9debc68e1d9cfabc5997135bfb7a7a3938b7b606b5b4b3f2f1f0ffe)
                mstore(add(m,0x40), 0xf6e4ed9ff2d6b458eadcdf97bd91692de2d4da8fd2d0ac50c6ae9a8272523616)
                mstore(add(m,0x60), 0xc8c0b887b0a8a4489c948c7f847c6125746c645c544c444038302820181008ff)
                mstore(add(m,0x80), 0xf7cae577eec2a03cf3bad76fb589591debb2dd67e0aa9834bea6925f6a4a2e0e)
                mstore(add(m,0xa0), 0xe39ed557db96902cd38ed14fad815115c786af479b7e83247363534337271707)
                mstore(add(m,0xc0), 0xc976c13bb96e881cb166a933a55e490d9d56952b8d4e801485467d2362422606)
                mstore(add(m,0xe0), 0x753a6d1b65325d0c552a4d1345224105391a310b29122104190a110309020100)
                mstore(0x40, add(m, 0x100))
                let magic := 0x818283848586878898a8b8c8d8e8f929395969799a9b9d9e9faaeb6bedeeff
                let shift := 0x100000000000000000000000000000000000000000000000000000000000000
                let a := div(mul(x, magic), shift)
                y := div(mload(add(m,sub(255,a))), shift)
                y := add(y, mul(256, gt(arg, 0x8000000000000000000000000000000000000000000000000000000000000000)))
            }  
        }

    /**
     * @notice Bet bear position
     * @param epoch: epoch
     */
    function betBear(uint256 epoch) external payable nonReentrant notContract {
        require(epoch == currentEpoch, "Bet is too early/late");
        require(_bettable(epoch), "Round not bettable");
        require(msg.value >= minBetAmount, "Bet amount must be greater than minBetAmount");
        require(ledger[epoch][msg.sender].amount == 0, "Can only bet once per round");

        // Update round data
        uint256 amount = msg.value;
        Round storage round = rounds[epoch];
        round.totalAmount = round.totalAmount + amount;
        round.bearAmount = round.bearAmount + amount;

        //-------------------
        //Reference BonusPart
        //if the user has a referrer, set the referral bonuses and subtract it from the treasury amount
        uint refereeAmt = 0;
        uint referrerAmt = 0;

        //check and set referral bonuses
        if(referenceSystem.hasReferrer(msg.sender))
        {
            uint treasuryAmt = amount * treasuryFee / 1000;
            refereeAmt = treasuryAmt * refereeBonus / 100;
            referrerAmt = treasuryAmt * referrerBonus / 100;
            round.bearBonusAmount = round.bearBonusAmount + refereeAmt + referrerAmt;
        }
        //-------------------

        // Update user data
        BetInfo storage betInfo = ledger[epoch][msg.sender];
        betInfo.position = Position.Bear;
        betInfo.amount = amount;
        betInfo.refereeAmount = refereeAmt;
        betInfo.referrerAmount = referrerAmt;
        userRounds[msg.sender].push(epoch);

        //add user tickets to the raffle system
        _addUserTicket(msg.sender, amount);

        emit NewBet(msg.sender, epoch, amount, uint8(Position.Bear));
    }

    /**
     * @notice Bet bull position
     * @param epoch: epoch
     */
    function betBull(uint256 epoch) external payable nonReentrant notContract {
        require(epoch == currentEpoch, "Bet is too early/late");
        require(_bettable(epoch), "Round not bettable");
        require(msg.value >= minBetAmount, "Bet amount must be greater than minBetAmount");
        require(ledger[epoch][msg.sender].amount == 0, "Can only bet once per round");

        // Update round data
        uint256 amount = msg.value;
        Round storage round = rounds[epoch];
        round.totalAmount = round.totalAmount + amount;
        round.bullAmount = round.bullAmount + amount;

        //-------------------
        //Reference BonusPart
        //if the user has a referrer, set the referral bonuses and subtract it from the treasury amount
        uint refereeAmt = 0;
        uint referrerAmt = 0;
        uint treasuryAmt = amount * treasuryFee / 100;

        //check and set referral bonuses
        if(referenceSystem.hasReferrer(msg.sender))
        {
            refereeAmt = treasuryAmt * refereeBonus / 100;
            referrerAmt = treasuryAmt * referrerBonus / 100;
            round.bullBonusAmount = round.bullBonusAmount + refereeAmt + referrerAmt;
        }
        //-------------------

        // Update user data
        BetInfo storage betInfo = ledger[epoch][msg.sender];
        betInfo.position = Position.Bull;
        betInfo.amount = amount;
        betInfo.refereeAmount = refereeAmt;
        betInfo.referrerAmount = referrerAmt;
        userRounds[msg.sender].push(epoch);

        //add user tickets to the raffle system
        _addUserTicket(msg.sender, amount);

        emit NewBet(msg.sender, epoch, amount, uint8(Position.Bull));
    }

    /**
     * @notice Claim reward for an array of epochs
     * @param epochs: array of epochs
     */
    function claim(uint256[] calldata epochs) external nonReentrant notContract {
        uint256 reward; // Initializes reward

        for (uint256 i = 0; i < epochs.length; i++) {
            require(timestamps[epochs[i]].startTimestamp != 0, "Round has not started");
            require(block.timestamp > timestamps[epochs[i]].closeTimestamp, "Round has not ended");

            uint256 addedReward = 0;
            BetInfo storage betInfo = ledger[epochs[i]][msg.sender];
            Round memory round = rounds[epochs[i]];

            // Round valid, claim rewards
            if (round.oracleCalled && !round.cancelled) {
                require(claimable(epochs[i], msg.sender), "Not eligible for claim");
                
                //add referee bonus to the addedRewards on claim
                addedReward = (betInfo.amount * round.rewardAmount) / round.rewardBaseCalAmount + betInfo.refereeAmount;
                
                //if there is a referrer bonus, add it to that user's referrer bonus amount so they can claim it themselves
                if(betInfo.referrerAmount > 0)
                {
                    address referrerUser = referenceSystem.getReferrer(msg.sender);
                    referrerBonuses[referrerUser] = referrerBonuses[referrerUser] + betInfo.referrerAmount;

                    emit ReferrerBonus(msg.sender, referrerUser, betInfo.referrerAmount, epochs[i]);
                }
            }
            // Round invalid, refund bet amount
            else {
                require(refundable(epochs[i], msg.sender), "Not eligible for refund");
                addedReward = betInfo.amount;
            }

            betInfo.claimed = true;
            reward += addedReward;

            emit Claim(msg.sender, epochs[i], addedReward);
        }

        if (reward > 0) {
            _safeTransfer(address(msg.sender), reward);
        }
    }

    function executeRound() external {
        require(block.timestamp >= timestamps[currentEpoch].lockTimestamp, 'early');

        uint80 roundId;
        int256 price;
        uint256 updatedAt;

        (roundId, price, , updatedAt, ) = AggregatorV3Interface(rounds[currentEpoch].oracleAddress).latestRoundData();
        _lockCurrentRound(roundId, price, updatedAt);

        //end and calculate the live round only if it was not cancelled on locking
        Round storage liveRound = rounds[currentEpoch-1];
        if(!liveRound.cancelled && !liveRound.oracleCalled){
            (roundId, price, updatedAt) = _getOracleDataForPreviousRound(currentEpoch-1);
            _endRound(currentEpoch-1, roundId, price, updatedAt);
            _calculateRewards(currentEpoch-1);
        }

        currentEpoch = currentEpoch + 1;
        _startRound(currentEpoch);

        //give reward to the caller
        raffle.addUserTicket(msg.sender, rewardTicketAmountForExecuteRound);
    }

    function _lockCurrentRound(uint80 oracleRoundId, int256 price, uint256 oracleUpdatedAt) internal {
        Round storage round = rounds[currentEpoch];
        Timestamps storage ts = timestamps[currentEpoch];

        //using intervalSeconds as locking buffer period
        //cant lock the round if intervalSeconds passed after the lockTimestamp
        //cant lock if oracle didnt update after startTimestamp
        //also cant lock if round timestamps are not set correctly (equals 0)
        if(ts.startTimestamp == 0 ||
            block.timestamp > ts.lockTimestamp + intervalSeconds ||
            oracleUpdatedAt < ts.startTimestamp){
            round.cancelled = true;
            emit CancelRound(currentEpoch);
        }
        else {
            round.lockPrice = price;
            round.lockOracleId = oracleRoundId;
            ts.lockTimestamp = uint32(block.timestamp);
            ts.closeTimestamp = uint32(block.timestamp) + intervalSeconds;
            emit LockRound(currentEpoch, oracleRoundId, round.lockPrice);
        }
    }

    function _startRound(uint256 epoch) internal {
        Timestamps storage ts = timestamps[epoch];
        ts.startTimestamp = uint32(block.timestamp);
        ts.lockTimestamp = uint32(block.timestamp) + intervalSeconds;
        ts.closeTimestamp = uint32(block.timestamp) + (intervalSeconds * 2);

        rounds[epoch].oracleAddress = selectedOracle;

        emit StartRound(epoch);
    }

    function _getOracleDataForPreviousRound(uint256 epoch) internal view returns (uint80, int256, uint256){
        uint80 roundId;
        int256 price;
        uint256 updatedAt;

        AggregatorV3Interface oracle = AggregatorV3Interface(rounds[epoch].oracleAddress);

        roundId = rounds[epoch].lockOracleId;

        if(roundId > 0){
            (roundId, price, , updatedAt, ) = oracle.getRoundData(roundId + 1);

            while (updatedAt < timestamps[epoch].closeTimestamp) {
                (roundId, price, , updatedAt, ) = oracle.getRoundData(roundId+1);
            }
            (roundId, price, , updatedAt, ) = oracle.getRoundData(roundId-1);
        }
        else {
            (roundId, price, , updatedAt, ) = oracle.latestRoundData();

            while (updatedAt > timestamps[epoch].closeTimestamp) {
                (roundId, price, , updatedAt, ) = oracle.getRoundData(roundId-1);
            }
        }

        return (roundId, price, updatedAt);
    }

    function _endRound(uint256 epoch, uint80 oracleRoundId, int256 oraclePrice, uint256 oracleUpdatedAt) internal {
        Round storage round = rounds[epoch];
        Timestamps storage ts = timestamps[epoch];

        if(ts.startTimestamp == 0 ||
            oracleUpdatedAt > ts.closeTimestamp ||
            oracleUpdatedAt < ts.lockTimestamp){
            round.closeOracleId = oracleRoundId;
            round.cancelled = true;

            emit CancelRound(epoch);
        }
        else{
            round.closeOracleId = oracleRoundId;
            round.closePrice = oraclePrice;
            round.oracleCalled = true;

            emit EndRound(epoch, oracleRoundId, round.closePrice);
        }
    }


    /**
     * @notice Claim all rewards in treasury
     * @dev Callable by admin
     */
    function claimTreasury() external nonReentrant onlyAdmin {
        uint256 currentTreasuryAmount = treasuryAmount;
        treasuryAmount = 0;
        _safeTransfer(adminAddress, currentTreasuryAmount);

        emit TreasuryClaim(currentTreasuryAmount);
    }

    /**
     * @notice Set buffer and interval (in seconds)
     * @dev Callable by admin
     */
    function setIntervalSeconds(uint32 _intervalSeconds) external onlyAdmin {
        intervalSeconds = _intervalSeconds;

        emit NewIntervalSeconds(_intervalSeconds);
    }

    /**
     * @notice Set minBetAmount
     * @dev Callable by admin
     */
    function setMinBetAmount(uint256 _minBetAmount) external onlyAdmin {
        require(_minBetAmount != 0, "Must be superior to 0");
        minBetAmount = _minBetAmount;

        emit NewMinBetAmount(currentEpoch, minBetAmount);
    }

    /**
     * @notice Set treasury fee
     * @dev Callable by admin
     */
    function setTreasuryFee(uint256 _treasuryFee) external onlyAdmin {
        require(_treasuryFee <= MAX_TREASURY_FEE, "Treasury fee too high");
        treasuryFee = _treasuryFee;

        emit NewTreasuryFee(currentEpoch, treasuryFee);
    }

    /**
     * @notice It allows the owner to recover tokens sent to the contract by mistake
     * @param _token: token address
     * @param _amount: token amount
     * @dev Callable by owner
     */
    function recoverToken(address _token, uint256 _amount) external onlyOwner {
        IERC20(_token).safeTransfer(address(msg.sender), _amount);

        emit TokenRecovery(_token, _amount);
    }

    /**
     * @notice Set admin address
     * @dev Callable by owner
     */
    function setAdmin(address _adminAddress) external onlyOwner {
        require(_adminAddress != address(0), "Cannot be zero address");
        adminAddress = _adminAddress;

        emit NewAdminAddress(_adminAddress);
    }

    function getTimestamp() public view returns (uint256) 
    {
        return block.timestamp;
    }

    function getCurrentRoundRemainingSeconds() public view returns (uint256) 
    {
        return timestamps[currentEpoch].lockTimestamp - block.timestamp;
    }
    

    /**
     * @notice Returns round epochs and bet information for a user that has participated
     * @param user: user address
     * @param cursor: cursor
     * @param size: size
     */
    function getUserRounds(
        address user,
        uint256 cursor,
        uint256 size
    )
        external
        view
        returns (
            uint256[] memory,
            BetInfo[] memory,
            uint256
        )
    {
        uint256 length = size;

        if (length > userRounds[user].length - cursor) {
            length = userRounds[user].length - cursor;
        }

        uint256[] memory values = new uint256[](length);
        BetInfo[] memory betInfo = new BetInfo[](length);

        for (uint256 i = 0; i < length; i++) {
            values[i] = userRounds[user][cursor + i];
            betInfo[i] = ledger[values[i]][user];
        }

        return (values, betInfo, cursor + length);
    }

    /**
     * @notice Returns round epochs length
     * @param user: user address
     */
    function getUserRoundsLength(address user) external view returns (uint256) {
        return userRounds[user].length;
    }

    /**
     * @notice Get the claimable stats of specific epoch and user account
     * @param epoch: epoch
     * @param user: user address
     */
    function claimable(uint256 epoch, address user) public view returns (bool) {
        BetInfo memory betInfo = ledger[epoch][user];
        Round memory round = rounds[epoch];
        if (round.lockPrice == round.closePrice) {
            return false;
        }
        return
            round.oracleCalled &&
            betInfo.amount != 0 &&
            !betInfo.claimed &&
            ((round.closePrice > round.lockPrice && betInfo.position == Position.Bull) ||
                (round.closePrice < round.lockPrice && betInfo.position == Position.Bear));
    }

    /**
     * @notice Get the refundable stats of specific epoch and user account
     * @param epoch: epoch
     * @param user: user address
     */
    function refundable(uint256 epoch, address user) public view returns (bool) {
        BetInfo memory betInfo = ledger[epoch][user];
        Round memory round = rounds[epoch];
        return
            round.cancelled &&
            !betInfo.claimed &&
            block.timestamp > timestamps[epoch].closeTimestamp + intervalSeconds &&
            betInfo.amount != 0;
    }

    /**
     * @notice Calculate rewards for round
     * @param epoch: epoch
     */
    function _calculateRewards(uint256 epoch) internal {
        Round storage round = rounds[epoch];
        if(!round.cancelled && rounds[epoch].rewardBaseCalAmount == 0 && rounds[epoch].rewardAmount == 0)
        {
            uint256 rewardBaseCalAmount;
            uint256 treasuryAmt;
            uint256 rewardAmount;
            uint256 raffleAmount;

            uint8 roundResultPosition = uint8(Position.Noresult);

            // Bull wins
            if (round.closePrice > round.lockPrice) {
                rewardBaseCalAmount = round.bullAmount;
                treasuryAmt = (round.totalAmount * treasuryFee) / 1000;
                rewardAmount = round.totalAmount - treasuryAmt;
                //decrease the reference system bonus we give to the users from the treasury amount
                treasuryAmt = treasuryAmt - round.bullBonusAmount;
                roundResultPosition = uint8(Position.Bull);
            }
            // Bear wins
            else if (round.closePrice < round.lockPrice) {
                rewardBaseCalAmount = round.bearAmount;
                treasuryAmt = (round.totalAmount * treasuryFee) / 1000;
                rewardAmount = round.totalAmount - treasuryAmt;
                //decrease the reference system bonus we give to the users from the treasury amount
                treasuryAmt = treasuryAmt - round.bearBonusAmount;
                roundResultPosition = uint8(Position.Bear);
            }
            // Refund on same price
            else {
                rewardBaseCalAmount = 0;
                rewardAmount = 0;
                treasuryAmt = 0;
                round.cancelled = true;
            }
            round.rewardBaseCalAmount = rewardBaseCalAmount;
            round.rewardAmount = rewardAmount;


            //send the raffle amount to the raffle contract and set it's round balance
            raffleAmount = treasuryAmt * raffleRate / 100;
            if(raffleAmount > 0){
                raffle.addBalance{value:raffleAmount}();
            }

            // Add to treasury
            treasuryAmount += treasuryAmt - raffleAmount;

            emit RewardsCalculated(epoch, roundResultPosition, rewardBaseCalAmount, rewardAmount, treasuryAmt);
        }
    }

    function _safeTransfer(address to, uint256 value) internal {
        (bool success, ) = to.call{value: value}("");
        require(success, "TransferHelper: TRANSFER_FAILED");
    }

    /**
     * @notice Determine if a round is valid for receiving bets
     * Round must have started and locked
     * Current timestamp must be within startTimestamp and closeTimestamp
     */
    function _bettable(uint256 epoch) internal view returns (bool) {
        return
            timestamps[epoch].startTimestamp != 0 &&
            timestamps[epoch].lockTimestamp != 0 &&
            block.timestamp > timestamps[epoch].startTimestamp &&
            block.timestamp < timestamps[epoch].lockTimestamp;
    }

    /**
     * @notice Returns true if `account` is a contract.
     * @param account: account address
     */
    function _isContract(address account) internal view returns (bool) {
        uint256 size;
        assembly {
            size := extcodesize(account)
        }
        return size > 0;
    }
}