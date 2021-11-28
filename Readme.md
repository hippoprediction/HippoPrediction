# HippoPrediction
## Chainlink Hackathon Fall 2021

HippoPrediction is an upgraded version of Pancakeswap Prediction game. Although it is very popular and very fun to play; we believe it can be further improved considering the soul of blockchains being decentralized in the first place.

We had 3 critical dimensions in mind while updating the existing structure of the game:

| A - Decentralization | B - Sharing with Community / Raffle System | C - Community Decisions and Voting |
| ------ | ------ | ------ |
|We targeted to remove a lot of centralized implementation, preventing any priviliged user to stop or cancel the game. We let the community to run the rounds and incentivize the executers with Raffle tickets | We believe in the power of community so we shared the commissions with them. Implemented our own raffle system to share prediction commissions | We wanted the community choose what they want to play. We implemented the voting system to choose the target token to play with |

---
# The problems and how we addressed them


## A - Decentralization:

Although the original predictions system is quite powerful and popular, there are centralized processes that are totally against the idea of blockchain.  Here are some problems we targeted and fixed:

#### Centralization problems and our fixes :
| Pancakeswap | HippoPrediction | 
| ------ | ------ |
|The system is totally dependent on the admin/operator’s backend script. They need to run the system every 5 min with their privileged account. | We have removed the modifiers of privileged accounts to run the system, now even if the operator does not run the script any member of the community can run it as it does not require any privileged modifier control. To incentivize the executors, we give them raffle tickets. Users can now execute the rounds before the developers to receive the incentives. |
|The system can be paused by the privileged accounts whenever they want. | The system will run as long as the community wants. Therefore we removed the privileged accounts' pausing abilities. |
|As the execution of a round depends on the privileged accounts, they can make an insider bet; then when they understand they are going to lose they can simply pause or don’t execute the round so the round will be cancelled and they get their bet back. | As our system is decentralized we don’t depend on the privileged accounts. The admin/operator can not pause the game. If they dont execute the round, any member of the community can execute it and the round will be completed. |
|The original system depends on latest round data of a price feed from the oracle to execute. If the round is not executed in a timely manner the round is cancelled. Similar to the insider abuse, if an attacker have a bet and understand he/she is going to lose, they can attack to the system or the backend to prevent the round being executed and get their bet back. | Our system can complete a round even after a year; thanks to the onchain data of Chainlink pricefeeds, if somehow our rounds are not executed in time, they are not paused and any member can execute the completion of an older round. The smart contract simply goes back and finds the latest answer of the oracle before that round’s ending time. |

---
## B - Sharing with Community:

In order to make the game more community based; we wanted to share the betting commissions with the community. This sharing happens with two different systems:

### -Raffle System:
Whenever a user makes a bet; they get tickets for the Raffle round depending on their bet amount. A portion of the commission from their bet is also sent to the Raffle contract.

This contract then will pick a winner among the ticket owners (everyone has a chance of ticketCount/totalTicketCount) using Chainlink VRF. All the raffle part of the commissions will be given to one lucky user.

### -Reference System:
As a community based system, we want to grow our community with their references. Therefore we give back the commission fees to referrers and referees.

Every user that used a reference code will simply get back a portion of their commissions when they claim a winning round. Every user can use only one reference code.

Every user that referred others; will get a portion of those users' betting commissions when they claim their winning round. Every user can refer unlimited users and get a part of their commission.

---
## C - Community Decisions

The core of our system is to bet if the price of a target token is going up or down in the next 5 minutes. Although it is quite fun to bet on any token, in the Pancakeswap system, target token is selected by the privileged accounts. We believe it should be selected by the community. 

Thanks to more than 60 Chainlink Pricefeed Oracles on Polygon updating every 27 seconds, we implemented a voting system to let our community decide on the target token. Whenever the voting round ends, the most voted Chainlink oracle takes up the place and starts feeding the new rounds’ price.

---

# Tech Stack

Thanks to the sponsors of Chainlink Hackathon, we were able to implement our strategy.

| Technology | Description |
| ------ | ------ |
| Polygon | Thanks to the fast transactions and low gas cost, the game runs smoothly and with less burden to the users |
| Chainlink PriceFeeds | Getting data from 60+ Chainlink Pricefeed Oracles. The target oracle is chosen by the community |
| Chainlink VRF | Getting random from Chainlink VRF Oracle for the Raffle System |
| Moralis | Thanks to syncing our contract events to the Moralis Database; we were able to get and calculate the data required for frontend. Especially on leaderboard, raffle and voting statistics and data. | 

---
# Contracts Deployed:
[HippoPrediction](https://mumbai.polygonscan.com/address/0xBD2e11702ABd48d9936A157c919B76e53a55F6A6#code)
[Raffle](https://mumbai.polygonscan.com/address/0x2dce8f6CE41Da154275E437D6F0c3B228A740444#code)
[Reference](https://mumbai.polygonscan.com/address/0x2f2e544F1183Afc6667E405eFb4e9acE18db539F#code)
[RandomNumberConsumer](https://mumbai.polygonscan.com/address/0x360ad85e11F234b48609d7F96e43a265B832926B#code)

[Frontend Repo](https://github.com/oalpay/bampan-predict)