# Base ecosystem open-source contracts for the community created by me

## MultiMarketPrediction Contract

A decentralized prediction market smart contract that allows the admin to create multiple markets using supported ERC20 tokens.  

- **Admin features**: add supported tokens, create markets, resolve outcomes, withdraw accidental ETH.  
- **User features**: place bets on market options, claim winnings if their chosen option wins.  
- **Security**: uses OpenZeppelin’s `ReentrancyGuard`, `Ownable`, and `SafeERC20` for safe and secure interactions.  
- **Mechanics**:  
  - Each market has a question, multiple options, and an end time.  
  - Users bet with supported tokens before the deadline.  
  - After resolution, winners can claim a proportional share of the total pot.  

