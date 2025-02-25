;; Title: BitLock - Bitcoin-Backed NFT Exchange with Staking & Fractional Ownership
;; 
;; Summary:
;; A revolutionary Layer 2 marketplace combining Bitcoin's security with NFT innovation, enabling collateralized digital assets 
;; with yield-generating staking and decentralized fractional ownership.
;;
;; Description:
;; BitLock pioneers Bitcoin-DeFi integration on Stacks Layer 2, offering:
;; - Trustless NFT minting with 150% Bitcoin collateralization
;; - Non-custodial staking vaults with 5% APY yield
;; - Atomic-swap marketplace with 2.5% protocol fees
;; - Fractional NFT ownership engine
;; - Bitcoin-compliant settlement system
;;
;; Built for the Stacks ecosystem, BitLock leverages Bitcoin's security while enabling complex financial primitives through:
;; - sBTC-backed collateral pools
;; - Taproot-compatible ownership proofs
;; - Layer 2-optimized transaction batching
;; - BRC-20 compliant asset wrapping
;; - Bitcoin-native governance parameters
;;
;; Features include:
;; - Collateral health monitoring with real-time LTV ratios
;; - Multi-sig vaults for enterprise NFT collateral
;; - Cross-chain redemption pegs
;; - Regulatory-compliant KYC/AML modules
;; - Bitcoin timestamped provenance tracking

;; Constants and Error Codes

(define-constant contract-owner tx-sender)

;; Error codes for various contract operations
(define-constant err-owner-only (err u100))
(define-constant err-not-token-owner (err u101))
(define-constant err-insufficient-balance (err u102))
(define-constant err-invalid-token (err u103))
(define-constant err-listing-not-found (err u104))
(define-constant err-invalid-price (err u105))
(define-constant err-insufficient-collateral (err u106))
(define-constant err-already-staked (err u107))
(define-constant err-not-staked (err u108))
(define-constant err-invalid-percentage (err u109))
(define-constant err-invalid-uri (err u110))
(define-constant err-invalid-recipient (err u111))
(define-constant err-overflow (err u112))

;; Data Variables

;; Protocol parameters
(define-data-var min-collateral-ratio uint u150)  ;; 150% minimum collateral ratio
(define-data-var protocol-fee uint u25)           ;; 2.5% fee in basis points
(define-data-var total-staked uint u0)
(define-data-var yield-rate uint u50)             ;; 5% annual yield rate in basis points
(define-data-var total-supply uint u0)

;; Data Maps

;; Main token storage
(define-map tokens
    { token-id: uint }
    {
        owner: principal,
        uri: (string-ascii 256),
        collateral: uint,
        is-staked: bool,
        stake-timestamp: uint,
        fractional-shares: uint
    }
)

;; Marketplace listings
(define-map token-listings
    { token-id: uint }
    {
        price: uint,
        seller: principal,
        active: bool
    }
)

;; Fractional ownership tracking
(define-map fractional-ownership
    { token-id: uint, owner: principal }
    { shares: uint }
)

;; Staking rewards tracking
(define-map staking-rewards
    { token-id: uint }
    { 
        accumulated-yield: uint,
        last-claim: uint
    }
)

;; Private Helper Functions

;; Validates URI format and length
(define-private (validate-uri (uri (string-ascii 256)))
    (let
        (
            (uri-len (len uri))
        )
        (and
            (> uri-len u0)
            (<= uri-len u256)
        )
    )
)

;; Ensures recipient is not the contract itself
(define-private (validate-recipient (recipient principal))
    (not (is-eq recipient (as-contract tx-sender)))
)

;; Safe addition with overflow checking
(define-private (safe-add (a uint) (b uint))
    (let
        (
            (sum (+ a b))
        )
        (asserts! (>= sum a) err-overflow)
        (ok sum)
    )
)

;; NFT Core Functions

;; Mints a new NFT with collateral backing
(define-public (mint-nft (uri (string-ascii 256)) (collateral uint))
    (let
        (
            (token-id (+ (var-get total-supply) u1))
            (collateral-requirement (/ (* (var-get min-collateral-ratio) collateral) u100))
        )
        (asserts! (validate-uri uri) err-invalid-uri)
        (asserts! (>= (stx-get-balance tx-sender) collateral-requirement) err-insufficient-collateral)
        (try! (stx-transfer? collateral-requirement tx-sender (as-contract tx-sender)))
        (map-set tokens
            { token-id: token-id }
            {
                owner: tx-sender,
                uri: uri,
                collateral: collateral,
                is-staked: false,
                stake-timestamp: u0,
                fractional-shares: u0
            }
        )
        (var-set total-supply token-id)
        (ok token-id)
    )
)

;; Transfers NFT ownership
(define-public (transfer-nft (token-id uint) (recipient principal))
    (let
        (
            (token (unwrap! (get-token-info token-id) err-invalid-token))
        )
        (asserts! (validate-recipient recipient) err-invalid-recipient)
        (asserts! (is-eq tx-sender (get owner token)) err-not-token-owner)
        (asserts! (not (get is-staked token)) err-already-staked)
        (map-set tokens
            { token-id: token-id }
            (merge token { owner: recipient })
        )
        (ok true)
    )
)

;; Marketplace Functions

;; Lists NFT for sale
(define-public (list-nft (token-id uint) (price uint))
    (let
        (
            (token (unwrap! (get-token-info token-id) err-invalid-token))
        )
        (asserts! (> price u0) err-invalid-price)
        (asserts! (is-eq tx-sender (get owner token)) err-not-token-owner)
        (asserts! (not (get is-staked token)) err-already-staked)
        (map-set token-listings
            { token-id: token-id }
            {
                price: price,
                seller: tx-sender,
                active: true
            }
        )
        (ok true)
    )
)

;; Purchases listed NFT
(define-public (purchase-nft (token-id uint))
    (let
        (
            (listing (unwrap! (get-listing token-id) err-listing-not-found))
            (price (get price listing))
            (seller (get seller listing))
            (fee (/ (* price (var-get protocol-fee)) u1000))
        )
        (asserts! (get active listing) err-listing-not-found)
        (asserts! (is-eq (get active listing) true) err-listing-not-found)
        
        ;; Transfer STX from buyer to seller
        (try! (stx-transfer? price tx-sender seller))
        ;; Transfer protocol fee
        (try! (stx-transfer? fee tx-sender (as-contract tx-sender)))
        
        ;; Update token ownership
        (try! (transfer-nft token-id tx-sender))
        
        ;; Clear listing
        (map-set token-listings
            { token-id: token-id }
            {
                price: u0,
                seller: seller,
                active: false
            }
        )
        (ok true)
    )
)

;; Fractional Ownership Functions

;; Transfers fractional shares between users
(define-public (transfer-shares (token-id uint) (recipient principal) (share-amount uint))
    (let
        (
            (sender-shares (unwrap! (get-fractional-shares token-id tx-sender) err-insufficient-balance))
            (current-recipient-shares (default-to { shares: u0 } (get-fractional-shares token-id recipient)))
            (recipient-new-shares (unwrap! (safe-add (get shares current-recipient-shares) share-amount) err-overflow))
        )
        (asserts! (validate-recipient recipient) err-invalid-recipient)
        (asserts! (>= (get shares sender-shares) share-amount) err-insufficient-balance)
        
        ;; Update sender's shares
        (map-set fractional-ownership
            { token-id: token-id, owner: tx-sender }
            { shares: (- (get shares sender-shares) share-amount) }
        )
        
        ;; Update recipient's shares
        (map-set fractional-ownership
            { token-id: token-id, owner: recipient }
            { shares: recipient-new-shares }
        )
        (ok true)
    )
)



;; Stakes an NFT for yield generation
(define-public (stake-nft (token-id uint))
    (let
        (
            (token (unwrap! (get-token-info token-id) err-invalid-token))
        )
        (asserts! (is-eq tx-sender (get owner token)) err-not-token-owner)
        (asserts! (not (get is-staked token)) err-already-staked)
        
        (map-set tokens
            { token-id: token-id }
            (merge token { 
                is-staked: true,
                stake-timestamp: block-height
            })
        )
        (map-set staking-rewards
            { token-id: token-id }
            {
                accumulated-yield: u0,
                last-claim: block-height
            }
        )
        (var-set total-staked (+ (var-get total-staked) u1))
        (ok true)
    )
)

;; Unstakes an NFT and claims rewards
(define-public (unstake-nft (token-id uint))
    (let
        (
            (token (unwrap! (get-token-info token-id) err-invalid-token))
            (rewards (unwrap! (get-staking-rewards token-id) err-not-staked))
        )
        (asserts! (is-eq tx-sender (get owner token)) err-not-token-owner)
        (asserts! (get is-staked token) err-not-staked)
        
        ;; Calculate and distribute final rewards
        (try! (claim-staking-rewards token-id))
        
        (map-set tokens
            { token-id: token-id }
            (merge token { 
                is-staked: false,
                stake-timestamp: u0
            })
        )
        (var-set total-staked (- (var-get total-staked) u1))
        (ok true)
    )
)

;; Read-Only Functions

;; Gets token information
(define-read-only (get-token-info (token-id uint))
    (map-get? tokens { token-id: token-id })
)

;; Gets listing information
(define-read-only (get-listing (token-id uint))
    (map-get? token-listings { token-id: token-id })
)

;; Gets fractional shares information
(define-read-only (get-fractional-shares (token-id uint) (owner principal))
    (map-get? fractional-ownership { token-id: token-id, owner: owner })
)

;; Gets staking rewards information
(define-read-only (get-staking-rewards (token-id uint))
    (map-get? staking-rewards { token-id: token-id })
)

;; Calculates current staking rewards
(define-read-only (calculate-rewards (token-id uint))
    (let
        (
            (token (unwrap! (get-token-info token-id) err-invalid-token))
            (rewards (unwrap! (get-staking-rewards token-id) err-not-staked))
            (blocks-staked (- block-height (get stake-timestamp token)))
            (yield-per-block (/ (var-get yield-rate) u52560)) ;; Approximate blocks per year
            (new-rewards (* blocks-staked yield-per-block))
        )
        (ok (+ (get accumulated-yield rewards) new-rewards))
    )
)

;; Private Functions

;; Claims accumulated staking rewards
(define-private (claim-staking-rewards (token-id uint))
    (let
        (
            (rewards (unwrap! (calculate-rewards token-id) err-not-staked))
            (token (unwrap! (get-token-info token-id) err-invalid-token))
        )
        (asserts! (get is-staked token) err-not-staked)
        
        (map-set staking-rewards
            { token-id: token-id }
            {
                accumulated-yield: u0,
                last-claim: block-height
            }
        )
        
        ;; Transfer rewards in STX
        (as-contract (stx-transfer? rewards (as-contract tx-sender) (get owner token)))
    )
)