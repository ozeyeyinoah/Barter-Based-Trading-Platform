(define-constant ERR-NOT-AUTHORIZED (err u100))
(define-constant ERR-TRADE-NOT-FOUND (err u101))
(define-constant ERR-INVALID-STATE (err u102))
(define-constant ERR-TIMEOUT (err u103))
(define-constant ERR-ALREADY-VOTED (err u104))
(define-constant ERR-INSUFFICIENT-DEPOSIT (err u105))
(define-constant ERR-DEPOSIT-ALREADY-MADE (err u106))
(define-constant ERR-NO-DEPOSIT-FOUND (err u107))

(define-constant TRADE-STATUS-PENDING u0)
(define-constant TRADE-STATUS-ACCEPTED u1)
(define-constant TRADE-STATUS-COMPLETED u2)
(define-constant TRADE-STATUS-DISPUTED u3)
(define-constant TRADE-STATUS-CANCELLED u4)

(define-constant DISPUTE-THRESHOLD u3)
(define-constant TRADE-TIMEOUT-BLOCKS u144)
(define-constant MIN-DEPOSIT-AMOUNT u1000000)

(define-map trades
    { trade-id: uint }
    {
        initiator: principal,
        counterparty: principal,
        initiator-offer: (string-ascii 256),
        counterparty-offer: (string-ascii 256),
        status: uint,
        created-at: uint,
        completed-at: uint
    }
)

(define-map dispute-votes
    { trade-id: uint, voter: principal }
    { vote: bool }
)

(define-map dispute-counts
    { trade-id: uint }
    { 
        positive-votes: uint,
        negative-votes: uint
    }
)

(define-data-var trade-nonce uint u0)

(define-map escrow-deposits
    { trade-id: uint, depositor: principal }
    {
        amount: uint,
        deposited-at: uint
    }
)

(define-map trade-deposit-requirements
    { trade-id: uint }
    {
        required-amount: uint,
        initiator-deposited: bool,
        counterparty-deposited: bool
    }
)

(define-read-only (get-trade (trade-id uint))
    (map-get? trades { trade-id: trade-id })
)

(define-read-only (get-dispute-votes (trade-id uint))
    (map-get? dispute-counts { trade-id: trade-id })
)

(define-read-only (get-deposit-requirements (trade-id uint))
    (map-get? trade-deposit-requirements { trade-id: trade-id })
)

(define-read-only (get-escrow-deposit (trade-id uint) (depositor principal))
    (map-get? escrow-deposits { trade-id: trade-id, depositor: depositor })
)

(define-public (create-trade-with-deposit (counterparty principal) (initiator-offer (string-ascii 256)) (counterparty-offer (string-ascii 256)) (deposit-amount uint))
    (let ((trade-id (var-get trade-nonce)))
        (asserts! (not (is-eq tx-sender counterparty)) ERR-INVALID-STATE)
        (asserts! (>= deposit-amount MIN-DEPOSIT-AMOUNT) ERR-INSUFFICIENT-DEPOSIT)
        
        (map-set trades
            { trade-id: trade-id }
            {
                initiator: tx-sender,
                counterparty: counterparty,
                initiator-offer: initiator-offer,
                counterparty-offer: counterparty-offer,
                status: TRADE-STATUS-PENDING,
                created-at: burn-block-height,
                completed-at: u0
            }
        )
        
        (map-set trade-deposit-requirements
            { trade-id: trade-id }
            {
                required-amount: deposit-amount,
                initiator-deposited: false,
                counterparty-deposited: false
            }
        )
        
        (var-set trade-nonce (+ trade-id u1))
        (ok trade-id)
    )
)

(define-public (create-trade (counterparty principal) (initiator-offer (string-ascii 256)) (counterparty-offer (string-ascii 256)))
    (let ((trade-id (var-get trade-nonce)))
        (asserts! (not (is-eq tx-sender counterparty)) ERR-INVALID-STATE)
        (map-set trades
            { trade-id: trade-id }
            {
                initiator: tx-sender,
                counterparty: counterparty,
                initiator-offer: initiator-offer,
                counterparty-offer: counterparty-offer,
                status: TRADE-STATUS-PENDING,
                created-at: burn-block-height,
                completed-at: u0
            }
        )
        (var-set trade-nonce (+ trade-id u1))
        (ok trade-id)
    )
)

(define-public (make-deposit (trade-id uint))
    (let ((trade (unwrap! (get-trade trade-id) ERR-TRADE-NOT-FOUND))
          (deposit-req (map-get? trade-deposit-requirements { trade-id: trade-id })))
        (asserts! (or
            (is-eq (get initiator trade) tx-sender)
            (is-eq (get counterparty trade) tx-sender)
        ) ERR-NOT-AUTHORIZED)
        (asserts! (is-eq (get status trade) TRADE-STATUS-PENDING) ERR-INVALID-STATE)
        (asserts! (is-some deposit-req) ERR-NO-DEPOSIT-FOUND)
        (asserts! (is-none (get-escrow-deposit trade-id tx-sender)) ERR-DEPOSIT-ALREADY-MADE)
        
        (let ((deposit-amount (get required-amount (unwrap-panic deposit-req))))
            (try! (stx-transfer? deposit-amount tx-sender (as-contract tx-sender)))
            
            (map-set escrow-deposits
                { trade-id: trade-id, depositor: tx-sender }
                {
                    amount: deposit-amount,
                    deposited-at: burn-block-height
                }
            )
            
            (let ((current-req (unwrap-panic deposit-req))
                  (is-initiator (is-eq (get initiator trade) tx-sender)))
                (map-set trade-deposit-requirements
                    { trade-id: trade-id }
                    (merge current-req {
                        initiator-deposited: (if is-initiator true (get initiator-deposited current-req)),
                        counterparty-deposited: (if (not is-initiator) true (get counterparty-deposited current-req))
                    })
                )
            )
            (ok true)
        )
    )
)

(define-public (accept-trade (trade-id uint))
    (let ((trade (unwrap! (get-trade trade-id) ERR-TRADE-NOT-FOUND)))
        (asserts! (is-eq (get counterparty trade) tx-sender) ERR-NOT-AUTHORIZED)
        (asserts! (is-eq (get status trade) TRADE-STATUS-PENDING) ERR-INVALID-STATE)
        (ok (map-set trades
            { trade-id: trade-id }
            (merge trade { status: TRADE-STATUS-ACCEPTED })
        ))
    )
)

(define-public (complete-trade-with-escrow (trade-id uint))
    (let ((trade (unwrap! (get-trade trade-id) ERR-TRADE-NOT-FOUND))
          (deposit-req (map-get? trade-deposit-requirements { trade-id: trade-id })))
        (asserts! (or
            (is-eq (get initiator trade) tx-sender)
            (is-eq (get counterparty trade) tx-sender)
        ) ERR-NOT-AUTHORIZED)
        (asserts! (is-eq (get status trade) TRADE-STATUS-ACCEPTED) ERR-INVALID-STATE)
        
        (match deposit-req
            requirements
            (begin
                (asserts! (get initiator-deposited requirements) ERR-NO-DEPOSIT-FOUND)
                (asserts! (get counterparty-deposited requirements) ERR-NO-DEPOSIT-FOUND)
                
                (let ((initiator-deposit (unwrap-panic (get-escrow-deposit trade-id (get initiator trade))))
                      (counterparty-deposit (unwrap-panic (get-escrow-deposit trade-id (get counterparty trade)))))
                    (try! (as-contract (stx-transfer? (get amount initiator-deposit) tx-sender (get initiator trade))))
                    (try! (as-contract (stx-transfer? (get amount counterparty-deposit) tx-sender (get counterparty trade))))
                )
            )
            true
        )
        
        (ok (map-set trades
            { trade-id: trade-id }
            (merge trade {
                status: TRADE-STATUS-COMPLETED,
                completed-at: burn-block-height
            })
        ))
    )
)

(define-public (complete-trade (trade-id uint))
    (let ((trade (unwrap! (get-trade trade-id) ERR-TRADE-NOT-FOUND)))
        (asserts! (or
            (is-eq (get initiator trade) tx-sender)
            (is-eq (get counterparty trade) tx-sender)
        ) ERR-NOT-AUTHORIZED)
        (asserts! (is-eq (get status trade) TRADE-STATUS-ACCEPTED) ERR-INVALID-STATE)
        (ok (map-set trades
            { trade-id: trade-id }
            (merge trade {
                status: TRADE-STATUS-COMPLETED,
                completed-at: burn-block-height
            })
        ))
    )
)

(define-public (dispute-trade (trade-id uint))
    (let ((trade (unwrap! (get-trade trade-id) ERR-TRADE-NOT-FOUND)))
        (asserts! (or
            (is-eq (get initiator trade) tx-sender)
            (is-eq (get counterparty trade) tx-sender)
        ) ERR-NOT-AUTHORIZED)
        (asserts! (is-eq (get status trade) TRADE-STATUS-ACCEPTED) ERR-INVALID-STATE)
        (ok (map-set trades
            { trade-id: trade-id }
            (merge trade { status: TRADE-STATUS-DISPUTED })
        ))
    )
)

(define-public (vote-on-dispute (trade-id uint) (vote bool))
    (let ((trade (unwrap! (get-trade trade-id) ERR-TRADE-NOT-FOUND))
          (current-votes (default-to { positive-votes: u0, negative-votes: u0 }
                        (map-get? dispute-counts { trade-id: trade-id }))))
        (asserts! (is-eq (get status trade) TRADE-STATUS-DISPUTED) ERR-INVALID-STATE)
        (asserts! (is-none (map-get? dispute-votes { trade-id: trade-id, voter: tx-sender })) ERR-ALREADY-VOTED)
        
        (map-set dispute-votes
            { trade-id: trade-id, voter: tx-sender }
            { vote: vote }
        )
        
        (map-set dispute-counts
            { trade-id: trade-id }
            {
                positive-votes: (if vote
                    (+ (get positive-votes current-votes) u1)
                    (get positive-votes current-votes)
                ),
                negative-votes: (if (not vote)
                    (+ (get negative-votes current-votes) u1)
                    (get negative-votes current-votes)
                )
            }
        )
        (ok true)
    )
)

(define-public (cancel-trade-with-escrow (trade-id uint))
    (let ((trade (unwrap! (get-trade trade-id) ERR-TRADE-NOT-FOUND))
          (deposit-req (map-get? trade-deposit-requirements { trade-id: trade-id })))
        (asserts! (or
            (is-eq (get initiator trade) tx-sender)
            (is-eq (get counterparty trade) tx-sender)
        ) ERR-NOT-AUTHORIZED)
        (asserts! (< (get status trade) TRADE-STATUS-COMPLETED) ERR-INVALID-STATE)
        
        (match deposit-req
            requirements
            (begin
                (match (get-escrow-deposit trade-id (get initiator trade))
                    initiator-deposit
                    (try! (as-contract (stx-transfer? (get amount initiator-deposit) tx-sender (get initiator trade))))
                    true
                )
                (match (get-escrow-deposit trade-id (get counterparty trade))
                    counterparty-deposit
                    (try! (as-contract (stx-transfer? (get amount counterparty-deposit) tx-sender (get counterparty trade))))
                    true
                )
            )
            true
        )
        
        (ok (map-set trades
            { trade-id: trade-id }
            (merge trade { status: TRADE-STATUS-CANCELLED })
        ))
    )
)

(define-public (cancel-trade (trade-id uint))
    (let ((trade (unwrap! (get-trade trade-id) ERR-TRADE-NOT-FOUND)))
        (asserts! (or
            (is-eq (get initiator trade) tx-sender)
            (is-eq (get counterparty trade) tx-sender)
        ) ERR-NOT-AUTHORIZED)
        (asserts! (< (get status trade) TRADE-STATUS-COMPLETED) ERR-INVALID-STATE)
        (ok (map-set trades
            { trade-id: trade-id }
            (merge trade { status: TRADE-STATUS-CANCELLED })
        ))
    )
)

(define-constant ERR-USER-NOT-FOUND (err u200))

(define-map user-reputation
    { user: principal }
    {
        total-trades: uint,
        successful-trades: uint,
        reputation-score: uint,
        last-updated: uint
    }
)

(define-read-only (get-user-reputation (user principal))
    (map-get? user-reputation { user: user })
)

(define-read-only (calculate-reputation-percentage (user principal))
    (match (get-user-reputation user)
        reputation-data
        (if (> (get total-trades reputation-data) u0)
            (ok (/ (* (get successful-trades reputation-data) u100) (get total-trades reputation-data)))
            (ok u0)
        )
        ERR-USER-NOT-FOUND
    )
)

(define-private (update-user-reputation (user principal) (successful bool))
    (let ((current-rep (default-to 
                        { total-trades: u0, successful-trades: u0, reputation-score: u0, last-updated: u0 }
                        (get-user-reputation user))))
        (map-set user-reputation
            { user: user }
            {
                total-trades: (+ (get total-trades current-rep) u1),
                successful-trades: (if successful 
                    (+ (get successful-trades current-rep) u1)
                    (get successful-trades current-rep)
                ),
                reputation-score: (if successful 
                    (+ (get reputation-score current-rep) u10)
                    (if (> (get reputation-score current-rep) u5)
                        (- (get reputation-score current-rep) u5)
                        u0
                    )
                ),
                last-updated: burn-block-height
            }
        )
    )
)

(define-public (complete-trade-with-reputation (trade-id uint))
    (let ((trade (unwrap! (get-trade trade-id) ERR-TRADE-NOT-FOUND)))
        (asserts! (or
            (is-eq (get initiator trade) tx-sender)
            (is-eq (get counterparty trade) tx-sender)
        ) ERR-NOT-AUTHORIZED)
        (asserts! (is-eq (get status trade) TRADE-STATUS-ACCEPTED) ERR-INVALID-STATE)
        
        (update-user-reputation (get initiator trade) true)
        (update-user-reputation (get counterparty trade) true)
        
        (ok (map-set trades
            { trade-id: trade-id }
            (merge trade {
                status: TRADE-STATUS-COMPLETED,
                completed-at: burn-block-height
            })
        ))
    )
)

(define-public (cancel-trade-with-reputation (trade-id uint))
    (let ((trade (unwrap! (get-trade trade-id) ERR-TRADE-NOT-FOUND)))
        (asserts! (or
            (is-eq (get initiator trade) tx-sender)
            (is-eq (get counterparty trade) tx-sender)
        ) ERR-NOT-AUTHORIZED)
        (asserts! (< (get status trade) TRADE-STATUS-COMPLETED) ERR-INVALID-STATE)
        
        (if (is-eq (get status trade) TRADE-STATUS-ACCEPTED)
            (update-user-reputation tx-sender false)
            true
        )
        
        (ok (map-set trades
            { trade-id: trade-id }
            (merge trade { status: TRADE-STATUS-CANCELLED })
        ))
    )
)

(define-constant CATEGORY-ELECTRONICS u1)
(define-constant CATEGORY-BOOKS u2)
(define-constant CATEGORY-CLOTHING u3)
(define-constant CATEGORY-SPORTS u4)
(define-constant CATEGORY-HOME u5)
(define-constant CATEGORY-AUTOMOTIVE u6)
(define-constant CATEGORY-COLLECTIBLES u7)
(define-constant CATEGORY-OTHER u8)

(define-constant ERR-INVALID-CATEGORY (err u300))
(define-constant MAX-RESULTS u50)

(define-map categorized-trades
    { trade-id: uint }
    {
        initiator: principal,
        counterparty: principal,
        initiator-offer: (string-ascii 256),
        counterparty-offer: (string-ascii 256),
        category: uint,
        status: uint,
        created-at: uint,
        completed-at: uint
    }
)

(define-map category-index
    { category: uint, index: uint }
    { trade-id: uint }
)

(define-map category-counts
    { category: uint }
    { count: uint }
)

(define-data-var categorized-trade-nonce uint u0)

(define-private (is-valid-category (category uint))
    (and (>= category u1) (<= category u8))
)

(define-read-only (get-categorized-trade (trade-id uint))
    (map-get? categorized-trades { trade-id: trade-id })
)

(define-read-only (get-category-count (category uint))
    (default-to u0 (get count (map-get? category-counts { category: category })))
)

(define-public (create-categorized-trade (counterparty principal) (initiator-offer (string-ascii 256)) (counterparty-offer (string-ascii 256)) (category uint))
    (let ((trade-id (var-get categorized-trade-nonce))
          (current-count (get-category-count category)))
        (asserts! (not (is-eq tx-sender counterparty)) ERR-INVALID-STATE)
        (asserts! (is-valid-category category) ERR-INVALID-CATEGORY)
        
        (map-set categorized-trades
            { trade-id: trade-id }
            {
                initiator: tx-sender,
                counterparty: counterparty,
                initiator-offer: initiator-offer,
                counterparty-offer: counterparty-offer,
                category: category,
                status: TRADE-STATUS-PENDING,
                created-at: burn-block-height,
                completed-at: u0
            }
        )
        
        (map-set category-index
            { category: category, index: current-count }
            { trade-id: trade-id }
        )
        
        (map-set category-counts
            { category: category }
            { count: (+ current-count u1) }
        )
        
        (var-set categorized-trade-nonce (+ trade-id u1))
        (ok trade-id)
    )
)

(define-read-only (get-trades-by-category (category uint) (start-index uint) (limit uint))
    (let ((actual-limit (if (> limit MAX-RESULTS) MAX-RESULTS limit))
          (category-count (get-category-count category)))
        (if (>= start-index category-count)
            (ok (list))
            (ok (list))
        )
    )
)

(define-read-only (search-trades-by-offer (search-term (string-ascii 50)))
    (ok (list))
)

(define-public (accept-categorized-trade (trade-id uint))
    (let ((trade (unwrap! (get-categorized-trade trade-id) ERR-TRADE-NOT-FOUND)))
        (asserts! (is-eq (get counterparty trade) tx-sender) ERR-NOT-AUTHORIZED)
        (asserts! (is-eq (get status trade) TRADE-STATUS-PENDING) ERR-INVALID-STATE)
        (ok (map-set categorized-trades
            { trade-id: trade-id }
            (merge trade { status: TRADE-STATUS-ACCEPTED })
        ))
    )
)