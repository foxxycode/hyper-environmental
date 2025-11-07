;; HyperEnvironmental - Decentralized Environmental Monitoring Network
;; A blockchain-based system for environmental data verification and impact tracking

;; Constants
(define-constant contract-owner tx-sender)
(define-constant err-owner-only (err u100))
(define-constant err-not-found (err u101))
(define-constant err-unauthorized (err u102))
(define-constant err-insufficient-stake (err u103))
(define-constant err-invalid-data (err u104))
(define-constant err-already-exists (err u105))
(define-constant err-threshold-not-met (err u106))

(define-constant min-validator-stake u1000000) ;; 1 STX minimum stake
(define-constant base-reward u100)
(define-constant emergency-threshold u90) ;; Critical pollution level

;; Data Variables
(define-data-var total-validators uint u0)
(define-data-var total-environmental-data uint u0)
(define-data-var governance-token-supply uint u0)
(define-data-var carbon-credit-supply uint u0)

;; Data Maps

;; Validator registry with staking and reputation
(define-map validators
  principal
  {
    stake: uint,
    accuracy-score: uint,
    total-submissions: uint,
    active: bool,
    joined-at: uint
  }
)

;; Environmental data points with verification
(define-map environmental-data
  uint
  {
    validator: principal,
    data-type: (string-ascii 50),
    value: uint,
    latitude: int,
    longitude: int,
    timestamp: uint,
    verified: bool,
    verification-count: uint
  }
)

;; Organization environmental impact scores
(define-map organization-scores
  principal
  {
    impact-score: uint,
    carbon-credits: uint,
    biodiversity-tokens: uint,
    pollution-penalties: uint,
    last-updated: uint
  }
)

;; Community governance tokens
(define-map governance-balances
  principal
  uint
)

;; Sensor network registry
(define-map sensor-networks
  uint
  {
    maintainer: principal,
    location-id: (string-ascii 100),
    sensor-count: uint,
    operational: bool,
    rewards-earned: uint
  }
)

;; Emergency alerts
(define-map emergency-alerts
  uint
  {
    alert-type: (string-ascii 50),
    severity: uint,
    location-id: (string-ascii 100),
    triggered-at: uint,
    resolved: bool,
    response-fund: uint
  }
)

;; Prediction market positions
(define-map prediction-positions
  { user: principal, prediction-id: uint }
  {
    stake-amount: uint,
    predicted-value: uint,
    locked: bool
  }
)

;; Read-only functions

(define-read-only (get-validator (validator principal))
  (map-get? validators validator)
)

(define-read-only (get-environmental-data (data-id uint))
  (map-get? environmental-data data-id)
)

(define-read-only (get-organization-score (org principal))
  (map-get? organization-scores org)
)

(define-read-only (get-governance-balance (account principal))
  (default-to u0 (map-get? governance-balances account))
)

(define-read-only (get-sensor-network (network-id uint))
  (map-get? sensor-networks network-id)
)

(define-read-only (get-emergency-alert (alert-id uint))
  (map-get? emergency-alerts alert-id)
)

(define-read-only (get-total-validators)
  (var-get total-validators)
)

(define-read-only (get-total-environmental-data)
  (var-get total-environmental-data)
)

(define-read-only (get-governance-token-supply)
  (var-get governance-token-supply)
)

(define-read-only (is-validator-active (validator principal))
  (match (map-get? validators validator)
    validator-data (get active validator-data)
    false
  )
)

;; Public functions

;; Register as a validator with stake
(define-public (register-validator (stake-amount uint))
  (let
    (
      (caller tx-sender)
    )
    (asserts! (>= stake-amount min-validator-stake) err-insufficient-stake)
    (asserts! (is-none (map-get? validators caller)) err-already-exists)
    
    ;; In production, this would transfer STX tokens as stake
    (map-set validators caller {
      stake: stake-amount,
      accuracy-score: u100,
      total-submissions: u0,
      active: true,
      joined-at: block-height
    })
    
    (var-set total-validators (+ (var-get total-validators) u1))
    (ok true)
  )
)

;; Submit environmental data point
(define-public (submit-environmental-data 
  (data-type (string-ascii 50))
  (value uint)
  (latitude int)
  (longitude int))
  (let
    (
      (caller tx-sender)
      (data-id (+ (var-get total-environmental-data) u1))
    )
    (asserts! (is-validator-active caller) err-unauthorized)
    (asserts! (> value u0) err-invalid-data)
    
    (map-set environmental-data data-id {
      validator: caller,
      data-type: data-type,
      value: value,
      latitude: latitude,
      longitude: longitude,
      timestamp: block-height,
      verified: false,
      verification-count: u0
    })
    
    ;; Update validator stats
    (match (map-get? validators caller)
      validator-data
        (map-set validators caller
          (merge validator-data { 
            total-submissions: (+ (get total-submissions validator-data) u1)
          })
        )
      false
    )
    
    (var-set total-environmental-data data-id)
    
    ;; Check for emergency conditions
    (if (>= value emergency-threshold)
      (begin
        (try! (trigger-emergency-alert data-type value latitude longitude))
        (ok data-id)
      )
      (ok data-id)
    )
  )
)

;; Verify environmental data
(define-public (verify-data (data-id uint))
  (let
    (
      (caller tx-sender)
    )
    (asserts! (is-validator-active caller) err-unauthorized)
    
    (match (map-get? environmental-data data-id)
      data-point
        (begin
          (asserts! (not (is-eq (get validator data-point) caller)) err-unauthorized)
          (map-set environmental-data data-id
            (merge data-point {
              verification-count: (+ (get verification-count data-point) u1),
              verified: (>= (+ (get verification-count data-point) u1) u3)
            })
          )
          
          ;; Reward validator for verification
          (unwrap! (mint-governance-tokens caller base-reward) err-invalid-data)
          (ok true)
        )
      err-not-found
    )
  )
)

;; Update organization environmental score
(define-public (update-organization-score 
  (organization principal)
  (impact-score uint)
  (carbon-credits uint)
  (biodiversity-tokens uint)
  (pollution-penalties uint))
  (begin
    (asserts! (is-validator-active tx-sender) err-unauthorized)
    
    (map-set organization-scores organization {
      impact-score: impact-score,
      carbon-credits: carbon-credits,
      biodiversity-tokens: biodiversity-tokens,
      pollution-penalties: pollution-penalties,
      last-updated: block-height
    })
    
    (ok true)
  )
)

;; Register sensor network
(define-public (register-sensor-network 
  (network-id uint)
  (location-id (string-ascii 100))
  (sensor-count uint))
  (let
    (
      (caller tx-sender)
    )
    (asserts! (is-none (map-get? sensor-networks network-id)) err-already-exists)
    
    (map-set sensor-networks network-id {
      maintainer: caller,
      location-id: location-id,
      sensor-count: sensor-count,
      operational: true,
      rewards-earned: u0
    })
    
    ;; Mint governance tokens for network setup
    (unwrap! (mint-governance-tokens caller (* sensor-count u10)) err-invalid-data)
    (ok true)
  )
)

;; Reward sensor network maintenance
(define-public (reward-network-maintenance (network-id uint))
  (match (map-get? sensor-networks network-id)
    network-data
      (let
        (
          (maintainer (get maintainer network-data))
          (reward (* (get sensor-count network-data) u5))
        )
        (asserts! (get operational network-data) err-invalid-data)
        
        (map-set sensor-networks network-id
          (merge network-data {
            rewards-earned: (+ (get rewards-earned network-data) reward)
          })
        )
        
        (unwrap! (mint-governance-tokens maintainer reward) err-invalid-data)
        (ok reward)
      )
    err-not-found
  )
)

;; Trigger emergency alert
(define-public (trigger-emergency-alert 
  (alert-type (string-ascii 50))
  (severity uint)
  (latitude int)
  (longitude int))
  (let
    (
      (alert-id (+ (var-get total-environmental-data) u1000))
      (location-str (concat (int-to-ascii latitude) (int-to-ascii longitude)))
    )
    (asserts! (is-validator-active tx-sender) err-unauthorized)
    (asserts! (>= severity emergency-threshold) err-threshold-not-met)
    
    (map-set emergency-alerts alert-id {
      alert-type: alert-type,
      severity: severity,
      location-id: location-str,
      triggered-at: block-height,
      resolved: false,
      response-fund: u0
    })
    
    (ok alert-id)
  )
)

;; Resolve emergency alert
(define-public (resolve-emergency (alert-id uint))
  (match (map-get? emergency-alerts alert-id)
    alert-data
      (begin
        (asserts! (is-validator-active tx-sender) err-unauthorized)
        (asserts! (not (get resolved alert-data)) err-invalid-data)
        
        (map-set emergency-alerts alert-id
          (merge alert-data { resolved: true })
        )
        (ok true)
      )
    err-not-found
  )
)

;; Submit prediction for environmental forecasting
(define-public (submit-prediction 
  (prediction-id uint)
  (stake-amount uint)
  (predicted-value uint))
  (let
    (
      (caller tx-sender)
    )
    (asserts! (>= (get-governance-balance caller) stake-amount) err-insufficient-stake)
    
    (map-set prediction-positions
      { user: caller, prediction-id: prediction-id }
      {
        stake-amount: stake-amount,
        predicted-value: predicted-value,
        locked: true
      }
    )
    
    (ok true)
  )
)

;; Mint governance tokens
(define-public (mint-governance-tokens (recipient principal) (amount uint))
  (begin
    (map-set governance-balances recipient
      (+ (get-governance-balance recipient) amount)
    )
    (var-set governance-token-supply 
      (+ (var-get governance-token-supply) amount)
    )
    (ok true)
  )
)

;; Transfer governance tokens
(define-public (transfer-governance-tokens 
  (recipient principal)
  (amount uint))
  (let
    (
      (caller tx-sender)
      (caller-balance (get-governance-balance caller))
    )
    (asserts! (>= caller-balance amount) err-insufficient-stake)
    
    (map-set governance-balances caller (- caller-balance amount))
    (map-set governance-balances recipient 
      (+ (get-governance-balance recipient) amount)
    )
    (ok true)
  )
)

;; Purchase carbon credits
(define-public (purchase-carbon-credits 
  (amount uint)
  (organization principal))
  (let
    (
      (caller tx-sender)
    )
    ;; In production, this would handle actual token transfers
    (match (map-get? organization-scores organization)
      org-data
        (begin
          (map-set organization-scores organization
            (merge org-data {
              carbon-credits: (+ (get carbon-credits org-data) amount)
            })
          )
          (var-set carbon-credit-supply 
            (+ (var-get carbon-credit-supply) amount)
          )
          (ok true)
        )
      ;; Initialize if organization doesn't exist
      (begin
        (map-set organization-scores organization {
          impact-score: u0,
          carbon-credits: amount,
          biodiversity-tokens: u0,
          pollution-penalties: u0,
          last-updated: block-height
        })
        (ok true)
      )
    )
  )
)

;; Admin function to deactivate validator
(define-public (deactivate-validator (validator principal))
  (begin
    (asserts! (is-eq tx-sender contract-owner) err-owner-only)
    
    (match (map-get? validators validator)
      validator-data
        (begin
          (map-set validators validator
            (merge validator-data { active: false })
          )
          (ok true)
        )
      err-not-found
    )
  )
)

;; Helper function to convert int to string (simplified)
(define-private (int-to-ascii (value int))
  (if (< value 0)
    "NEG"
    "POS"
  )
)
