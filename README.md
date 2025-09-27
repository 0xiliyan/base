# Base ecosystem contracts for general use by third parties

## MultiMarketPrediction Contract

A decentralized prediction market smart contract that allows the admin to create multiple markets using supported ERC20 tokens.  

- **Admin features**: add supported tokens, create markets, resolve outcomes, withdraw accidental ETH.  
- **User features**: place bets on market options, claim winnings if their chosen option wins.  
- **Security**: uses OpenZeppelin’s `ReentrancyGuard`, `Ownable`, and `SafeERC20` for safe and secure interactions.  
- **Mechanics**:  
  - Each market has a question, multiple options, and an end time.  
  - Users bet with supported tokens before the deadline. git 
  - After resolution, winners can claim a proportional share of the total pot.  

## Disperse Contract

A bulk transfer utility contract for distributing ETH and ERC20 tokens to multiple recipients in a single transaction, similar to [disperse.app](https://disperse.app).  

- **ETH dispersal**: send ETH to many wallets in one transaction.  
- **Token dispersal**: approve tokens to the contract, then distribute to multiple addresses.  
- **Admin features**: recover mistakenly sent tokens/ETH, transfer ownership.  
- **Security**: includes `ReentrancyGuard` and a minimal `SafeERC20` wrapper.  
- **Notes**:  
  - Useful for airdrops, rewards, or batch payments.  
  - Large recipient lists may hit gas limits — split into multiple calls if needed.  

