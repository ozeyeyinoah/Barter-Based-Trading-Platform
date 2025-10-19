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

;; ===========================================
;; TRADE STATISTICS & ANALYTICS FEATURE
;; ===========================================

;; Error constants for analytics
(define-constant ERR-INVALID-TIME-PERIOD (err u500))
(define-constant ERR-ANALYTICS-DATA-NOT-FOUND (err u501))
(define-constant ERR-INSUFFICIENT-DATA (err u502))

;; Time period constants
(define-constant PERIOD-DAILY u1)
(define-constant PERIOD-WEEKLY u2)
(define-constant PERIOD-MONTHLY u3)
(define-constant PERIOD-ALL-TIME u4)

;; Platform-wide statistics
(define-map platform-statistics
    { period: uint, start-block: uint }
    {
        total-trades-created: uint,
        total-trades-completed: uint,
        total-trades-disputed: uint,
        total-trades-cancelled: uint,
        total-volume-stx: uint,
        active-users: uint,
        last-updated: uint
    }
)

;; User performance analytics
(define-map user-analytics
    { user: principal, period: uint, start-block: uint }
    {
        trades-initiated: uint,
        trades-completed-as-initiator: uint,
        trades-completed-as-counterparty: uint,
        trades-disputed-initiated: uint,
        trades-disputed-received: uint,
        average-completion-time: uint,
        total-escrow-deposits: uint,
        last-activity-block: uint
    }
)

;; Category performance tracking
(define-map category-analytics
    { category: uint, period: uint, start-block: uint }
    {
        total-trades: uint,
        completed-trades: uint,
        disputed-trades: uint,
        success-rate: uint,
        most-active-user: principal,
        last-updated: uint
    }
)

;; Time-based metrics for trend analysis
(define-map time-metrics
    { metric-type: (string-ascii 32), block-height: uint }
    {
        value: uint,
        recorded-at: uint
    }
)

;; Top performers tracking
(define-map leaderboard-rankings
    { ranking-type: (string-ascii 32), position: uint }
    {
        user: principal,
        score: uint,
        last-updated: uint
    }
)

;; Data variables for analytics
(define-data-var analytics-enabled bool true)
(define-data-var last-analytics-update uint u0)
(define-data-var total-platform-trades uint u0)
(define-data-var total-platform-volume uint u0)

;; Read-only functions for statistics retrieval
(define-read-only (get-platform-statistics (period uint) (start-block uint))
    (map-get? platform-statistics { period: period, start-block: start-block })
)

(define-read-only (get-user-analytics (user principal) (period uint) (start-block uint))
    (map-get? user-analytics { user: user, period: period, start-block: start-block })
)

(define-read-only (get-category-analytics (category uint) (period uint) (start-block uint))
    (map-get? category-analytics { category: category, period: period, start-block: start-block })
)

(define-read-only (get-time-metric (metric-type (string-ascii 32)) (target-block uint))
    (map-get? time-metrics { metric-type: metric-type, block-height: target-block })
)

(define-read-only (get-leaderboard-position (ranking-type (string-ascii 32)) (position uint))
    (map-get? leaderboard-rankings { ranking-type: ranking-type, position: position })
)

(define-read-only (get-total-platform-metrics)
    (ok {
        total-trades: (var-get total-platform-trades),
        total-volume: (var-get total-platform-volume),
        last-updated: (var-get last-analytics-update),
        analytics-enabled: (var-get analytics-enabled)
    })
)

(define-read-only (calculate-user-success-rate (user principal) (period uint) (start-block uint))
    (match (get-user-analytics user period start-block)
        analytics
        (let ((total-trades (+ (get trades-initiated analytics) 
                             (+ (get trades-completed-as-initiator analytics) 
                                (get trades-completed-as-counterparty analytics))))
              (successful-trades (+ (get trades-completed-as-initiator analytics) 
                                   (get trades-completed-as-counterparty analytics))))
            (if (> total-trades u0)
                (ok (/ (* successful-trades u100) total-trades))
                (ok u0)
            )
        )
        ERR-ANALYTICS-DATA-NOT-FOUND
    )
)

(define-read-only (get-category-success-rate (category uint) (period uint) (start-block uint))
    (match (get-category-analytics category period start-block)
        analytics
        (if (> (get total-trades analytics) u0)
            (ok (get success-rate analytics))
            (ok u0)
        )
        ERR-ANALYTICS-DATA-NOT-FOUND
    )
)

(define-read-only (is-analytics-enabled)
    (var-get analytics-enabled)
)

(define-read-only (get-platform-overview)
    (ok {
        total-trades: (var-get total-platform-trades),
        total-volume: (var-get total-platform-volume),
        current-trade-nonce: (var-get trade-nonce),
        analytics-enabled: (var-get analytics-enabled),
        last-analytics-update: (var-get last-analytics-update)
    })
)

(define-read-only (get-user-trade-summary (user principal))
    (match (get-user-analytics user PERIOD-ALL-TIME u0)
        analytics
        (ok {
            total-initiated: (get trades-initiated analytics),
            total-completed: (+ (get trades-completed-as-initiator analytics) 
                              (get trades-completed-as-counterparty analytics)),
            total-disputed: (+ (get trades-disputed-initiated analytics) 
                             (get trades-disputed-received analytics)),
            total-deposits: (get total-escrow-deposits analytics),
            last-activity: (get last-activity-block analytics)
        })
        (ok {
            total-initiated: u0,
            total-completed: u0,
            total-disputed: u0,
            total-deposits: u0,
            last-activity: u0
        })
    )
)

;; Private functions for statistics updates
(define-private (update-platform-statistics (period uint) (start-block uint) (trade-status uint) (volume uint))
    (let ((current-stats (default-to
                           { total-trades-created: u0, total-trades-completed: u0, 
                             total-trades-disputed: u0, total-trades-cancelled: u0,
                             total-volume-stx: u0, active-users: u0, last-updated: u0 }
                           (get-platform-statistics period start-block))))
        (map-set platform-statistics
            { period: period, start-block: start-block }
            {
                total-trades-created: (if (is-eq trade-status TRADE-STATUS-PENDING)
                    (+ (get total-trades-created current-stats) u1)
                    (get total-trades-created current-stats)
                ),
                total-trades-completed: (if (is-eq trade-status TRADE-STATUS-COMPLETED)
                    (+ (get total-trades-completed current-stats) u1)
                    (get total-trades-completed current-stats)
                ),
                total-trades-disputed: (if (is-eq trade-status TRADE-STATUS-DISPUTED)
                    (+ (get total-trades-disputed current-stats) u1)
                    (get total-trades-disputed current-stats)
                ),
                total-trades-cancelled: (if (is-eq trade-status TRADE-STATUS-CANCELLED)
                    (+ (get total-trades-cancelled current-stats) u1)
                    (get total-trades-cancelled current-stats)
                ),
                total-volume-stx: (+ (get total-volume-stx current-stats) volume),
                active-users: (get active-users current-stats),
                last-updated: burn-block-height
            }
        )
        true
    )
)

(define-private (update-user-analytics (user principal) (period uint) (start-block uint) (action (string-ascii 32)) (trade-id uint))
    (let ((current-analytics (default-to
                               { trades-initiated: u0, trades-completed-as-initiator: u0,
                                 trades-completed-as-counterparty: u0, trades-disputed-initiated: u0,
                                 trades-disputed-received: u0, average-completion-time: u0,
                                 total-escrow-deposits: u0, last-activity-block: u0 }
                               (get-user-analytics user period start-block))))
        (map-set user-analytics
            { user: user, period: period, start-block: start-block }
            {
                trades-initiated: (if (is-eq action "initiated")
                    (+ (get trades-initiated current-analytics) u1)
                    (get trades-initiated current-analytics)
                ),
                trades-completed-as-initiator: (if (is-eq action "completed-initiator")
                    (+ (get trades-completed-as-initiator current-analytics) u1)
                    (get trades-completed-as-initiator current-analytics)
                ),
                trades-completed-as-counterparty: (if (is-eq action "completed-counterparty")
                    (+ (get trades-completed-as-counterparty current-analytics) u1)
                    (get trades-completed-as-counterparty current-analytics)
                ),
                trades-disputed-initiated: (if (is-eq action "disputed-initiated")
                    (+ (get trades-disputed-initiated current-analytics) u1)
                    (get trades-disputed-initiated current-analytics)
                ),
                trades-disputed-received: (if (is-eq action "disputed-received")
                    (+ (get trades-disputed-received current-analytics) u1)
                    (get trades-disputed-received current-analytics)
                ),
                average-completion-time: (get average-completion-time current-analytics),
                total-escrow-deposits: (if (is-eq action "deposit")
                    (+ (get total-escrow-deposits current-analytics) u1)
                    (get total-escrow-deposits current-analytics)
                ),
                last-activity-block: burn-block-height
            }
        )
        true
    )
)

(define-private (record-time-metric (metric-type (string-ascii 32)) (value uint))
    (map-set time-metrics
        { metric-type: metric-type, block-height: burn-block-height }
        {
            value: value,
            recorded-at: burn-block-height
        }
    )
)

(define-private (update-leaderboard (ranking-type (string-ascii 32)) (user principal) (score uint))
    (map-set leaderboard-rankings
        { ranking-type: ranking-type, position: u1 }
        {
            user: user,
            score: score,
            last-updated: burn-block-height
        }
    )
)

;; Public functions for analytics management
(define-public (toggle-analytics)
    (begin
        (var-set analytics-enabled (not (var-get analytics-enabled)))
        (ok (var-get analytics-enabled))
    )
)

(define-public (record-daily-metrics)
    (let ((current-block burn-block-height)
          (total-trades (var-get total-platform-trades)))
        (record-time-metric "daily-trades" total-trades)
        (record-time-metric "daily-volume" (var-get total-platform-volume))
        (var-set last-analytics-update current-block)
        (ok true)
    )
)

(define-public (get-top-traders (limit uint))
    (let ((actual-limit (if (> limit u10) u10 limit)))
        (ok (list))
    )
)

(define-public (get-trending-categories (period uint))
    (if (and (>= period u1) (<= period u4))
        (ok (list))
        ERR-INVALID-TIME-PERIOD
    )
)

;; Enhanced trade creation with analytics
(define-public (create-trade-with-analytics (counterparty principal) (initiator-offer (string-ascii 256)) (counterparty-offer (string-ascii 256)))
    (let ((trade-id (var-get trade-nonce)))
        (asserts! (not (is-eq tx-sender counterparty)) ERR-INVALID-STATE)
        
        ;; Create the trade
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
        
        ;; Update analytics if enabled
        (if (var-get analytics-enabled)
            (begin
                (update-platform-statistics PERIOD-ALL-TIME u0 TRADE-STATUS-PENDING u0)
                (update-user-analytics tx-sender PERIOD-ALL-TIME u0 "initiated" trade-id)
                (var-set total-platform-trades (+ (var-get total-platform-trades) u1))
                true
            )
            true
        )
        
        (var-set trade-nonce (+ trade-id u1))
        (ok trade-id)
    )
)

;; Enhanced trade completion with analytics
(define-public (complete-trade-with-analytics (trade-id uint))
    (let ((trade (unwrap! (get-trade trade-id) ERR-TRADE-NOT-FOUND)))
        (asserts! (or
            (is-eq (get initiator trade) tx-sender)
            (is-eq (get counterparty trade) tx-sender)
        ) ERR-NOT-AUTHORIZED)
        (asserts! (is-eq (get status trade) TRADE-STATUS-ACCEPTED) ERR-INVALID-STATE)
        
        ;; Complete the trade
        (map-set trades
            { trade-id: trade-id }
            (merge trade {
                status: TRADE-STATUS-COMPLETED,
                completed-at: burn-block-height
            })
        )
        
        ;; Update analytics if enabled
        (if (var-get analytics-enabled)
            (begin
                (update-platform-statistics PERIOD-ALL-TIME u0 TRADE-STATUS-COMPLETED u0)
                (if (is-eq (get initiator trade) tx-sender)
                    (update-user-analytics tx-sender PERIOD-ALL-TIME u0 "completed-initiator" trade-id)
                    (update-user-analytics tx-sender PERIOD-ALL-TIME u0 "completed-counterparty" trade-id)
                )
                true
            )
            true
        )
        
        (ok true)
    )
)

;; Analytics-enabled dispute function
(define-public (dispute-trade-with-analytics (trade-id uint))
    (let ((trade (unwrap! (get-trade trade-id) ERR-TRADE-NOT-FOUND)))
        (asserts! (or
            (is-eq (get initiator trade) tx-sender)
            (is-eq (get counterparty trade) tx-sender)
        ) ERR-NOT-AUTHORIZED)
        (asserts! (is-eq (get status trade) TRADE-STATUS-ACCEPTED) ERR-INVALID-STATE)
        
        ;; Update trade status
        (map-set trades
            { trade-id: trade-id }
            (merge trade { status: TRADE-STATUS-DISPUTED })
        )
        
        ;; Update analytics if enabled
        (if (var-get analytics-enabled)
            (begin
                (update-platform-statistics PERIOD-ALL-TIME u0 TRADE-STATUS-DISPUTED u0)
                (update-user-analytics tx-sender PERIOD-ALL-TIME u0 "disputed-initiated" trade-id)
                ;; Update analytics for the other party
                (let ((other-party (if (is-eq (get initiator trade) tx-sender)
                                     (get counterparty trade)
                                     (get initiator trade))))
                    (update-user-analytics other-party PERIOD-ALL-TIME u0 "disputed-received" trade-id)
                )
                true
            )
            true
        )
        
        (ok true)
    )
)

;; Batch analytics update function
(define-public (update-analytics-batch (trade-ids (list 10 uint)))
    (begin
        (asserts! (var-get analytics-enabled) (err u999))
        (var-set last-analytics-update burn-block-height)
        (ok (len trade-ids))
    )
)
