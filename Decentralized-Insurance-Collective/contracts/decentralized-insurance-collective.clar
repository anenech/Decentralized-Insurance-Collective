;; Decentralized Insurance Collective Smart Contract
;; A mutual insurance system where participants pool resources, vote on claim validity, and receive rewards for accurate risk assessment

;; Constants
(define-constant contract-owner tx-sender)
(define-constant err-owner-only (err u100))
(define-constant err-not-member (err u101))
(define-constant err-insufficient-funds (err u102))
(define-constant err-already-member (err u103))
(define-constant err-claim-not-found (err u104))
(define-constant err-already-voted (err u105))
(define-constant err-voting-period-ended (err u106))
(define-constant err-invalid-amount (err u107))
(define-constant err-claim-already-processed (err u108))
(define-constant err-minimum-stake-required (err u109))

;; Data Variables
(define-data-var next-claim-id uint u1)
(define-data-var total-pool-balance uint u0)
(define-data-var minimum-stake uint u1000000) ;; 1 STX minimum stake
(define-data-var voting-period uint u144) ;; ~24 hours in blocks
(define-data-var quorum-threshold uint u60) ;; 60% quorum required

;; Data Maps
(define-map members principal 
  {
    stake: uint,
    reputation-score: uint,
    claims-voted: uint,
    accurate-votes: uint,
    join-block: uint,
    active: bool
  }
)

(define-map insurance-claims uint
  {
    claimant: principal,
    amount: uint,
    description: (string-ascii 500),
    evidence-hash: (string-ascii 64),
    status: (string-ascii 20), ;; "pending", "approved", "rejected"
    votes-for: uint,
    votes-against: uint,
    total-voters: uint,
    created-block: uint,
    voting-deadline: uint,
    processed: bool
  }
)

(define-map claim-votes {claim-id: uint, voter: principal}
  {
    vote: bool, ;; true for approve, false for reject
    stake-weight: uint,
    block-height: uint
  }
)

(define-map member-claims principal (list 50 uint))

;; Private Functions
(define-private (calculate-voting-power (member principal))
  (let (
    (member-data (unwrap! (map-get? members member) u0))
    (stake (get stake member-data))
    (reputation (get reputation-score member-data))
  )
    (+ stake (/ (* reputation u100) u10)) ;; Stake + (reputation * 10)
  )
)

(define-private (update-reputation (voter principal) (accurate bool))
  (let (
    (member-data (unwrap! (map-get? members voter) false))
    (current-reputation (get reputation-score member-data))
    (claims-voted (get claims-voted member-data))
    (accurate-votes (get accurate-votes member-data))
  )
    (map-set members voter
      (merge member-data {
        claims-voted: (+ claims-voted u1),
        accurate-votes: (if accurate (+ accurate-votes u1) accurate-votes),
        reputation-score: (if accurate (+ current-reputation u10) 
                                      (if (> current-reputation u5) (- current-reputation u5) u0))
      })
    )
    true
  )
)

(define-private (is-quorum-met (claim-id uint))
  (let (
    (claim-data (unwrap! (map-get? insurance-claims claim-id) false))
    (total-voters (get total-voters claim-data))
    (total-members (len (var-get total-pool-balance))) ;; Approximation
    (required-votes (/ (* total-members (var-get quorum-threshold)) u100))
  )
    (>= total-voters required-votes)
  )
)

;; Public Functions

;; Join the insurance collective
(define-public (join-collective (stake-amount uint))
  (let (
    (current-member (map-get? members tx-sender))
  )
    (asserts! (is-none current-member) err-already-member)
    (asserts! (>= stake-amount (var-get minimum-stake)) err-minimum-stake-required)
    
    (try! (stx-transfer? stake-amount tx-sender (as-contract tx-sender)))
    
    (map-set members tx-sender {
      stake: stake-amount,
      reputation-score: u100, ;; Starting reputation
      claims-voted: u0,
      accurate-votes: u0,
      join-block: block-height,
      active: true
    })
    
    (var-set total-pool-balance (+ (var-get total-pool-balance) stake-amount))
    (ok true)
  )
)

;; Increase stake in the collective
(define-public (increase-stake (additional-amount uint))
  (let (
    (member-data (unwrap! (map-get? members tx-sender) err-not-member))
    (current-stake (get stake member-data))
  )
    (asserts! (> additional-amount u0) err-invalid-amount)
    
    (try! (stx-transfer? additional-amount tx-sender (as-contract tx-sender)))
    
    (map-set members tx-sender
      (merge member-data {stake: (+ current-stake additional-amount)})
    )
    
    (var-set total-pool-balance (+ (var-get total-pool-balance) additional-amount))
    (ok true)
  )
)

;; Submit an insurance claim
(define-public (submit-claim (amount uint) (description (string-ascii 500)) (evidence-hash (string-ascii 64)))
  (let (
    (claim-id (var-get next-claim-id))
    (member-data (unwrap! (map-get? members tx-sender) err-not-member))
    (current-claims (default-to (list) (map-get? member-claims tx-sender)))
  )
    (asserts! (get active member-data) err-not-member)
    (asserts! (> amount u0) err-invalid-amount)
    (asserts! (<= amount (var-get total-pool-balance)) err-insufficient-funds)
    
    (map-set insurance-claims claim-id {
      claimant: tx-sender,
      amount: amount,
      description: description,
      evidence-hash: evidence-hash,
      status: "pending",
      votes-for: u0,
      votes-against: u0,
      total-voters: u0,
      created-block: block-height,
      voting-deadline: (+ block-height (var-get voting-period)),
      processed: false
    })
    
    (map-set member-claims tx-sender (unwrap! (as-max-len? (append current-claims claim-id) u50) (err u999)))
    (var-set next-claim-id (+ claim-id u1))
    
    (ok claim-id)
  )
)

;; Vote on a claim
(define-public (vote-on-claim (claim-id uint) (approve bool))
  (let (
    (claim-data (unwrap! (map-get? insurance-claims claim-id) err-claim-not-found))
    (member-data (unwrap! (map-get? members tx-sender) err-not-member))
    (existing-vote (map-get? claim-votes {claim-id: claim-id, voter: tx-sender}))
    (voting-power (calculate-voting-power tx-sender))
  )
    (asserts! (is-none existing-vote) err-already-voted)
    (asserts! (get active member-data) err-not-member)
    (asserts! (<= block-height (get voting-deadline claim-data)) err-voting-period-ended)
    (asserts! (not (get processed claim-data)) err-claim-already-processed)
    (asserts! (not (is-eq tx-sender (get claimant claim-data))) err-not-member) ;; Can't vote on own claim
    
    (map-set claim-votes {claim-id: claim-id, voter: tx-sender} {
      vote: approve,
      stake-weight: voting-power,
      block-height: block-height
    })
    
    (map-set insurance-claims claim-id
      (merge claim-data {
        votes-for: (if approve (+ (get votes-for claim-data) voting-power) (get votes-for claim-data)),
        votes-against: (if approve (get votes-against claim-data) (+ (get votes-against claim-data) voting-power)),
        total-voters: (+ (get total-voters claim-data) u1)
      })
    )
    
    (ok true)
  )
)

;; Process a claim after voting period
(define-public (process-claim (claim-id uint))
  (let (
    (claim-data (unwrap! (map-get? insurance-claims claim-id) err-claim-not-found))
    (votes-for (get votes-for claim-data))
    (votes-against (get votes-against claim-data))
    (claim-amount (get amount claim-data))
    (claimant (get claimant claim-data))
  )
    (asserts! (> block-height (get voting-deadline claim-data)) err-voting-period-ended)
    (asserts! (not (get processed claim-data)) err-claim-already-processed)
    (asserts! (is-quorum-met claim-id) (err u110)) ;; Quorum not met
    
    (let (
      (approved (> votes-for votes-against))
      (new-status (if approved "approved" "rejected"))
    )
      (map-set insurance-claims claim-id
        (merge claim-data {
          status: new-status,
          processed: true
        })
      )
      
      (if approved
        (begin
          (try! (as-contract (stx-transfer? claim-amount tx-sender claimant)))
          (var-set total-pool-balance (- (var-get total-pool-balance) claim-amount))
        )
        true
      )
      
      ;; Update reputation for voters
      (ok approved)
    )
  )
)

;; Leave the collective (withdraw stake)
(define-public (leave-collective)
  (let (
    (member-data (unwrap! (map-get? members tx-sender) err-not-member))
    (stake (get stake member-data))
  )
    (asserts! (get active member-data) err-not-member)
    
    (try! (as-contract (stx-transfer? stake tx-sender tx-sender)))
    
    (map-set members tx-sender
      (merge member-data {active: false, stake: u0})
    )
    
    (var-set total-pool-balance (- (var-get total-pool-balance) stake))
    (ok true)
  )
)

;; Read-only functions

(define-read-only (get-member-info (member principal))
  (map-get? members member)
)

(define-read-only (get-claim-info (claim-id uint))
  (map-get? insurance-claims claim-id)
)

(define-read-only (get-member-claims (member principal))
  (default-to (list) (map-get? member-claims member))
)

(define-read-only (get-pool-balance)
  (var-get total-pool-balance)
)

(define-read-only (get-voting-power (member principal))
  (calculate-voting-power member)
)

(define-read-only (get-claim-vote (claim-id uint) (voter principal))
  (map-get? claim-votes {claim-id: claim-id, voter: voter})
)

(define-read-only (get-contract-info)
  {
    total-pool-balance: (var-get total-pool-balance),
    next-claim-id: (var-get next-claim-id),
    minimum-stake: (var-get minimum-stake),
    voting-period: (var-get voting-period),
    quorum-threshold: (var-get quorum-threshold)
  }
)

;; Admin functions (only contract owner can call)

(define-public (update-minimum-stake (new-minimum uint))
  (begin
    (asserts! (is-eq tx-sender contract-owner) err-owner-only)
    (var-set minimum-stake new-minimum)
    (ok true)
  )
)

(define-public (update-voting-period (new-period uint))
  (begin
    (asserts! (is-eq tx-sender contract-owner) err-owner-only)
    (var-set voting-period new-period)
    (ok true)
  )
)