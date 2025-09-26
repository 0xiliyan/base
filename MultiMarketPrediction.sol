// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/utils/ReentrancyGuard.sol"; // OZ v5 path
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

contract MultiMarketPrediction is ReentrancyGuard, Ownable {
    using SafeERC20 for IERC20;

    // Structs
    struct Market {
        IERC20 bettingToken;
        string question;
        string[] options;
        uint256 endTime;
        bool isResolved;
        uint256 winningOptionIndex; // type(uint256).max if unresolved
        uint256 totalPot;
    }

    struct Bet {
        address bettor;
        uint256 amount;
        uint256 optionIndex;
    }

    // State variables
    IERC20[] public supportedTokens;
    uint256 public nextMarketId;

    // Market storage
    mapping(uint256 => Market) public markets;
    mapping(uint256 => Bet[]) private marketBets;
    mapping(uint256 => mapping(uint256 => uint256)) private optionTotals;
    mapping(uint256 => mapping(address => bool)) private hasClaimed; // prevent double-claim

    // Events
    event SupportedTokenAdded(address indexed token);
    event MarketCreated(uint256 indexed marketId, string question, string[] options, uint256 endTime);
    event BetPlaced(uint256 indexed marketId, address indexed bettor, uint256 amount, uint256 optionIndex);
    event MarketResolved(uint256 indexed marketId, uint256 winningOptionIndex);
    event WinningsClaimed(uint256 indexed marketId, address indexed bettor, uint256 amount);
    event ETHWithdrawn(address indexed recipient, uint256 amount);

    // Errors
    error UnsupportedToken();
    error BettingClosed();
    error InvalidOption();
    error AlreadyResolved();
    error NothingToClaim();
    error InvalidResolutionTime();
    error ZeroAddress();
    error MarketNotResolved();
    error AlreadyClaimed();
    error NotAWinner();
    error NoWinners();

    constructor() Ownable(msg.sender) {
        // Start with no supported tokens (admin must add them)
    }

    // --- Core Functions ---

    // Add a supported betting token (admin only)
    function addSupportedToken(address _tokenAddress) external onlyOwner {
        if (_tokenAddress == address(0)) revert ZeroAddress();
        supportedTokens.push(IERC20(_tokenAddress));
        emit SupportedTokenAdded(_tokenAddress);
    }

    // Create a new market (admin only)
    function createMarket(
        IERC20 _bettingToken,
        string memory _question,
        string[] memory _options,
        uint256 _endTime
    ) external onlyOwner nonReentrant {
        if (_options.length < 2) revert("At least 2 options required");
        if (_endTime <= block.timestamp) revert InvalidResolutionTime();
        if (!isSupportedToken(_bettingToken)) revert UnsupportedToken();

        uint256 marketId = nextMarketId++;
        markets[marketId] = Market({
            bettingToken: _bettingToken,
            question: _question,
            options: _options,
            endTime: _endTime,
            isResolved: false,
            winningOptionIndex: type(uint256).max, // Unresolved
            totalPot: 0
        });

        // Initialize per-option totals
        for (uint256 i = 0; i < _options.length; i++) {
            optionTotals[marketId][i] = 0;
        }

        emit MarketCreated(marketId, _question, _options, _endTime);
    }

    // Place a bet on a market option
    function placeBet(
        uint256 _marketId,
        uint256 _optionIndex,
        uint256 _amount
    ) external nonReentrant {
        Market storage market = markets[_marketId];
        if (block.timestamp >= market.endTime) revert BettingClosed();
        if (market.isResolved) revert AlreadyResolved();
        if (_optionIndex >= market.options.length) revert InvalidOption();
        if (_amount == 0) revert("Amount must be > 0");

        IERC20 token = market.bettingToken;
        token.safeTransferFrom(msg.sender, address(this), _amount);

        // Record bet
        marketBets[_marketId].push(Bet({
            bettor: msg.sender,
            amount: _amount,
            optionIndex: _optionIndex
        }));

        // Update totals
        market.totalPot += _amount;
        optionTotals[_marketId][_optionIndex] += _amount;

        emit BetPlaced(_marketId, msg.sender, _amount, _optionIndex);
    }

    // Resolve a market (admin only)
    function resolveMarket(
        uint256 _marketId,
        uint256 _winningOptionIndex
    ) external onlyOwner nonReentrant {
        Market storage market = markets[_marketId];
        if (block.timestamp < market.endTime) revert InvalidResolutionTime();
        if (market.isResolved) revert AlreadyResolved();
        if (_winningOptionIndex >= market.options.length) revert InvalidOption();

        market.isResolved = true;
        market.winningOptionIndex = _winningOptionIndex;

        emit MarketResolved(_marketId, _winningOptionIndex);
    }

    // Claim winnings for a market (winners take all; losers get nothing)
    function claimWinnings(uint256 _marketId) external nonReentrant {
        Market storage market = markets[_marketId];
        if (!market.isResolved) revert MarketNotResolved();
        if (hasClaimed[_marketId][msg.sender]) revert AlreadyClaimed();

        uint256 winningOption = market.winningOptionIndex;
        uint256 userWinningBet = 0;

        // Sum user's bets on the winning option
        Bet[] storage bets = marketBets[_marketId];
        for (uint256 i = 0; i < bets.length; i++) {
            if (bets[i].bettor == msg.sender && bets[i].optionIndex == winningOption) {
                userWinningBet += bets[i].amount;
            }
        }

        if (userWinningBet == 0) revert NotAWinner();

        uint256 optionTotal = optionTotals[_marketId][winningOption];
        if (optionTotal == 0) revert NoWinners(); // defensive: avoid div-by-zero

        uint256 payout = (userWinningBet * market.totalPot) / optionTotal;

        hasClaimed[_marketId][msg.sender] = true; // effects before interaction
        market.bettingToken.safeTransfer(msg.sender, payout);

        emit WinningsClaimed(_marketId, msg.sender, payout);
    }

    // Admin: Withdraw accidental ETH
    function withdrawETH(address payable _recipient, uint256 _amount) external onlyOwner nonReentrant {
        if (_recipient == address(0)) revert ZeroAddress();
        _recipient.transfer(_amount);
        emit ETHWithdrawn(_recipient, _amount);
    }

    // --- View Functions ---

    // Check if a token is supported
    function isSupportedToken(IERC20 _token) public view returns (bool) {
        for (uint256 i = 0; i < supportedTokens.length; i++) {
            if (address(supportedTokens[i]) == address(_token)) {
                return true;
            }
        }
        return false;
    }

    // Get all market IDs
    function getMarketIds() external view returns (uint256[] memory) {
        uint256[] memory ids = new uint256[](nextMarketId);
        for (uint256 i = 0; i < nextMarketId; i++) {
            ids[i] = i;
        }
        return ids;
    }

    // Get market info (question, options, endTime, etc.)
    function getMarketInfo(uint256 _marketId) external view returns (
        string memory question,
        string[] memory options,
        uint256 endTime,
        bool isResolved,
        uint256 winningOptionIndex,
        uint256 totalPot,
        address bettingToken
    ) {
        Market memory market = markets[_marketId];
        return (
            market.question,
            market.options,
            market.endTime,
            market.isResolved,
            market.winningOptionIndex,
            market.totalPot,
            address(market.bettingToken)
        );
    }

    // Get a user's bets for a market
    function getUserBets(uint256 _marketId, address _user) external view returns (Bet[] memory) {
        Bet[] storage bets = marketBets[_marketId];

        // First pass: count
        uint256 count = 0;
        for (uint256 i = 0; i < bets.length; i++) {
            if (bets[i].bettor == _user) {
                count++;
            }
        }

        // Allocate and fill
        Bet[] memory userBets = new Bet[](count);
        uint256 idx = 0;
        for (uint256 i = 0; i < bets.length; i++) {
            if (bets[i].bettor == _user) {
                userBets[idx] = bets[i];
                idx++;
            }
        }
        return userBets;
    }

    // Get total bets per option
    function getOptionTotals(uint256 _marketId) external view returns (uint256[] memory) {
        Market memory market = markets[_marketId];
        uint256[] memory totals = new uint256[](market.options.length);
        for (uint256 i = 0; i < market.options.length; i++) {
            totals[i] = optionTotals[_marketId][i];
        }
        return totals;
    }

    // Check if a user has already claimed (optional helper)
    function hasUserClaimed(uint256 _marketId, address _user) external view returns (bool) {
        return hasClaimed[_marketId][_user];
    }
}
