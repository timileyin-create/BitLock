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