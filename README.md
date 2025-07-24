# Decentralized Insurance Collective

A mutual insurance system built on the Stacks blockchain where participants pool resources, vote on claim validity, and receive rewards for accurate risk assessment.

## Overview

This smart contract implements a decentralized insurance collective where:
- Members stake STX tokens to join the collective
- Claims are submitted with evidence and voted on democratically
- Voting power is weighted by stake and reputation
- Accurate voting increases reputation and voting power
- Claims are automatically processed based on majority vote

## Features

### Core Functionality
- **Member Registration**: Join by staking minimum STX amount
- **Claim Submission**: Submit insurance claims with evidence
- **Democratic Voting**: Vote on claim validity with weighted voting power
- **Reputation System**: Build reputation through accurate voting
- **Automatic Processing**: Claims processed automatically after voting period
- **Stake Management**: Increase stake or withdraw from collective

### Security Features
- Quorum requirements for valid votes
- Time-limited voting periods
- Anti-fraud measures (can't vote on own claims)
- Proper access controls and error handling

## Contract Functions

### Public Functions

#### `join-collective(stake-amount)`
Join the insurance collective by staking STX tokens.
- **Parameters**: `stake-amount` (uint) - Amount of STX to stake
- **Minimum**: 1 STX (1,000,000 micro-STX)

#### `submit-claim(amount, description, evidence-hash)`
Submit an insurance claim for review.
- **Parameters**: 
  - `amount` (uint) - Claim amount in micro-STX
  - `description` (string-ascii 500) - Claim description
  - `evidence-hash` (string-ascii 64) - Hash of evidence documents

#### `vote-on-claim(claim-id, approve)`
Vote on a pending claim.
- **Parameters**:
  - `claim-id` (uint) - ID of the claim to vote on
  - `approve` (bool) - True to approve, false to reject

#### `process-claim(claim-id)`
Process a claim after voting period ends.
- **Parameters**: `claim-id` (uint) - ID of the claim to process

### Read-Only Functions

#### `get-member-info(member)`
Get member information including stake and reputation.

#### `get-claim-info(claim-id)`
Get detailed information about a specific claim.

#### `get-pool-balance()`
Get total balance of the insurance pool.

## Usage Example

```clarity
;; Join the collective with 5 STX
(contract-call? .decentralized-insurance-collective join-collective u5000000)

;; Submit a claim for 2 STX
(contract-call? .decentralized-insurance-collective submit-claim 
  u2000000 
  "Car accident damage" 
  "hash-of-accident-photos-and-reports")

;; Vote to approve claim #1
(contract-call? .decentralized-insurance-collective vote-on-claim u1 true)

;; Process claim #1 after voting period
(contract-call? .decentralized-insurance-collective process-claim u1)