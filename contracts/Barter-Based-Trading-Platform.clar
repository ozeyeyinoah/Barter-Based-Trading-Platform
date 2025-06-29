(define-constant ERR-NOT-AUTHORIZED (err u100))
(define-constant ERR-TRADE-NOT-FOUND (err u101))
(define-constant ERR-INVALID-STATE (err u102))
(define-constant ERR-TIMEOUT (err u103))
(define-constant ERR-ALREADY-VOTED (err u104))

(define-constant TRADE-STATUS-PENDING u0)
(define-constant TRADE-STATUS-ACCEPTED u1)
(define-constant TRADE-STATUS-COMPLETED u2)
(define-constant TRADE-STATUS-DISPUTED u3)
(define-constant TRADE-STATUS-CANCELLED u4)

(define-constant DISPUTE-THRESHOLD u3)
(define-constant TRADE-TIMEOUT-BLOCKS u144)

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

(define-read-only (get-trade (trade-id uint))
    (map-get? trades { trade-id: trade-id })
)

(define-read-only (get-dispute-votes (trade-id uint))
    (map-get? dispute-counts { trade-id: trade-id })
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
