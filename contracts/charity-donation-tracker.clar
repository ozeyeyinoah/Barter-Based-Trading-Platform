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

;; ===========================================
;; USER REPUTATION SYSTEM FEATURE
;; ===========================================

;; Error constants for reputation system
(define-constant ERR-RATING-OUT-OF-RANGE (err u600))
(define-constant ERR-SELF-RATING-NOT-ALLOWED (err u601))
(define-constant ERR-RATING-ALREADY-EXISTS (err u602))
(define-constant ERR-USER-NOT-FOUND (err u603))
(define-constant ERR-INSUFFICIENT-RATINGS (err u604))
(define-constant ERR-FEEDBACK-TOO-LONG (err u605))
(define-constant ERR-INVALID-REPUTATION-LEVEL (err u606))
(define-constant ERR-REPUTATION-SYSTEM-DISABLED (err u607))

;; Reputation level constants
(define-constant REPUTATION-NOVICE u1)
(define-constant REPUTATION-BRONZE u2)
(define-constant REPUTATION-SILVER u3)
(define-constant REPUTATION-GOLD u4)
(define-constant REPUTATION-PLATINUM u5)

;; Rating constants
(define-constant MIN-RATING u1)
(define-constant MAX-RATING u5)
(define-constant MAX-FEEDBACK-LENGTH u512)
(define-constant MIN-RATINGS-FOR-LEVEL u5)
(define-constant REPUTATION-THRESHOLD-BRONZE u35) ;; 3.5 * 10 for decimal precision
(define-constant REPUTATION-THRESHOLD-SILVER u40) ;; 4.0 * 10
(define-constant REPUTATION-THRESHOLD-GOLD u45)   ;; 4.5 * 10
(define-constant REPUTATION-THRESHOLD-PLATINUM u48) ;; 4.8 * 10

;; User reputation profiles
(define-map user-reputation
    { user: principal }
    {
        total-ratings: uint,
        total-score: uint,
        average-rating: uint, ;; Multiplied by 10 for decimal precision
        reputation-level: uint,
        positive-feedback-count: uint,
        negative-feedback-count: uint,
        neutral-feedback-count: uint,
        last-rating-received: uint,
        reputation-points: uint,
        is-verified: bool
    }
)

;; Individual ratings given by users
(define-map user-ratings
    { rater: principal, rated-user: principal }
    {
        rating: uint,
        feedback: (string-ascii 512),
        created-at: uint,
        is-anonymous: bool
    }
)

;; Reputation badges and achievements
(define-map user-badges
    { user: principal, badge-type: (string-ascii 64) }
    {
        earned-at: uint,
        badge-level: uint,
        is-active: bool
    }
)

;; Reputation system configuration
(define-map reputation-config
    { config-key: (string-ascii 32) }
    {
        config-value: uint,
        last-updated: uint
    }
)

;; Data variables for reputation system
(define-data-var reputation-system-enabled bool true)
(define-data-var total-reputation-points uint u0)
(define-data-var reputation-admin principal tx-sender)
(define-data-var minimum-rating-threshold uint u3) ;; Minimum average needed to be considered good

;; Read-only functions for reputation queries
(define-read-only (get-user-reputation (user principal))
    (map-get? user-reputation { user: user })
)

(define-read-only (get-user-rating (rater principal) (rated-user principal))
    (map-get? user-ratings { rater: rater, rated-user: rated-user })
)

(define-read-only (get-user-badge (user principal) (badge-type (string-ascii 64)))
    (map-get? user-badges { user: user, badge-type: badge-type })
)

(define-read-only (get-reputation-config (config-key (string-ascii 32)))
    (map-get? reputation-config { config-key: config-key })
)

(define-read-only (is-reputation-system-enabled)
    (var-get reputation-system-enabled)
)

(define-read-only (calculate-reputation-level (average-rating uint) (total-ratings uint))
    (if (< total-ratings MIN-RATINGS-FOR-LEVEL)
        (ok REPUTATION-NOVICE)
        (if (>= average-rating REPUTATION-THRESHOLD-PLATINUM)
            (ok REPUTATION-PLATINUM)
            (if (>= average-rating REPUTATION-THRESHOLD-GOLD)
                (ok REPUTATION-GOLD)
                (if (>= average-rating REPUTATION-THRESHOLD-SILVER)
                    (ok REPUTATION-SILVER)
                    (if (>= average-rating REPUTATION-THRESHOLD-BRONZE)
                        (ok REPUTATION-BRONZE)
                        (ok REPUTATION-NOVICE)
                    )
                )
            )
        )
    )
)

(define-read-only (get-user-reputation-summary (user principal))
    (match (get-user-reputation user)
        reputation
        (ok {
            user: user,
            total-ratings: (get total-ratings reputation),
            average-rating: (get average-rating reputation),
            reputation-level: (get reputation-level reputation),
            total-feedback: (+ (+ (get positive-feedback-count reputation)
                                 (get negative-feedback-count reputation))
                              (get neutral-feedback-count reputation)),
            reputation-points: (get reputation-points reputation),
            is-verified: (get is-verified reputation),
            last-rated: (get last-rating-received reputation)
        })
        (ok {
            user: user,
            total-ratings: u0,
            average-rating: u0,
            reputation-level: REPUTATION-NOVICE,
            total-feedback: u0,
            reputation-points: u0,
            is-verified: false,
            last-rated: u0
        })
    )
)

(define-read-only (get-reputation-level-name (level uint))
    (if (is-eq level REPUTATION-NOVICE)
        (ok "Novice")
        (if (is-eq level REPUTATION-BRONZE)
            (ok "Bronze")
            (if (is-eq level REPUTATION-SILVER)
                (ok "Silver")
                (if (is-eq level REPUTATION-GOLD)
                    (ok "Gold")
                    (if (is-eq level REPUTATION-PLATINUM)
                        (ok "Platinum")
                        ERR-INVALID-REPUTATION-LEVEL
                    )
                )
            )
        )
    )
)

(define-read-only (check-user-eligibility (user principal) (minimum-level uint))
    (match (get-user-reputation user)
        reputation
        (ok (>= (get reputation-level reputation) minimum-level))
        (ok false)
    )
)

(define-read-only (get-reputation-statistics)
    (ok {
        total-reputation-points: (var-get total-reputation-points),
        system-enabled: (var-get reputation-system-enabled),
        minimum-rating-threshold: (var-get minimum-rating-threshold),
        current-admin: (var-get reputation-admin)
    })
)

;; Private helper functions for reputation calculations
(define-private (update-user-reputation-stats (user principal) (new-rating uint) (feedback-type (string-ascii 16)))
    (let ((current-reputation (default-to
                                { total-ratings: u0, total-score: u0, average-rating: u0,
                                  reputation-level: REPUTATION-NOVICE, positive-feedback-count: u0,
                                  negative-feedback-count: u0, neutral-feedback-count: u0,
                                  last-rating-received: u0, reputation-points: u0, is-verified: false }
                                (get-user-reputation user)))
          (new-total-ratings (+ (get total-ratings current-reputation) u1))
          (new-total-score (+ (get total-score current-reputation) new-rating))
          (new-average-rating (/ (* new-total-score u10) new-total-ratings))
          (new-level (unwrap-panic (calculate-reputation-level new-average-rating new-total-ratings)))
          (reputation-points-earned (calculate-reputation-points new-rating new-level)))
        
        (map-set user-reputation
            { user: user }
            {
                total-ratings: new-total-ratings,
                total-score: new-total-score,
                average-rating: new-average-rating,
                reputation-level: new-level,
                positive-feedback-count: (if (is-eq feedback-type "positive")
                    (+ (get positive-feedback-count current-reputation) u1)
                    (get positive-feedback-count current-reputation)
                ),
                negative-feedback-count: (if (is-eq feedback-type "negative")
                    (+ (get negative-feedback-count current-reputation) u1)
                    (get negative-feedback-count current-reputation)
                ),
                neutral-feedback-count: (if (is-eq feedback-type "neutral")
                    (+ (get neutral-feedback-count current-reputation) u1)
                    (get neutral-feedback-count current-reputation)
                ),
                last-rating-received: burn-block-height,
                reputation-points: (+ (get reputation-points current-reputation) reputation-points-earned),
                is-verified: (get is-verified current-reputation)
            }
        )
        
        ;; Update global reputation points
        (var-set total-reputation-points (+ (var-get total-reputation-points) reputation-points-earned))
        true
    )
)

(define-private (calculate-reputation-points (rating uint) (level uint))
    (let ((base-points (if (>= rating u4) u10 (if (>= rating u3) u5 u1)))
          (level-multiplier (if (is-eq level REPUTATION-PLATINUM) u5
                             (if (is-eq level REPUTATION-GOLD) u4
                               (if (is-eq level REPUTATION-SILVER) u3
                                 (if (is-eq level REPUTATION-BRONZE) u2 u1))))))
        (* base-points level-multiplier)
    )
)

(define-private (determine-feedback-type (rating uint))
    (if (>= rating u4)
        "positive"
        (if (>= rating u3)
            "neutral"
            "negative"
        )
    )
)

(define-private (award-badge-if-eligible (user principal) (badge-type (string-ascii 64)) (condition bool))
    (if condition
        (begin
            (map-set user-badges
                { user: user, badge-type: badge-type }
                {
                    earned-at: burn-block-height,
                    badge-level: u1,
                    is-active: true
                }
            )
            true
        )
        true
    )
)

;; Public functions for reputation management
(define-public (rate-user (rated-user principal) (rating uint) (feedback (string-ascii 512)) (is-anonymous bool))
    (begin
        (asserts! (var-get reputation-system-enabled) ERR-REPUTATION-SYSTEM-DISABLED)
        (asserts! (not (is-eq tx-sender rated-user)) ERR-SELF-RATING-NOT-ALLOWED)
        (asserts! (and (>= rating MIN-RATING) (<= rating MAX-RATING)) ERR-RATING-OUT-OF-RANGE)
        (asserts! (<= (len feedback) MAX-FEEDBACK-LENGTH) ERR-FEEDBACK-TOO-LONG)
        (asserts! (is-none (get-user-rating tx-sender rated-user)) ERR-RATING-ALREADY-EXISTS)
        
        ;; Store the rating
        (map-set user-ratings
            { rater: tx-sender, rated-user: rated-user }
            {
                rating: rating,
                feedback: feedback,
                created-at: burn-block-height,
                is-anonymous: is-anonymous
            }
        )
        
        ;; Update reputation statistics
        (let ((feedback-type (determine-feedback-type rating)))
            (update-user-reputation-stats rated-user rating feedback-type)
        )
        
        ;; Check for badge eligibility
        (match (get-user-reputation rated-user)
            reputation
            (begin
                (award-badge-if-eligible rated-user "first-rating" (is-eq (get total-ratings reputation) u1))
                (award-badge-if-eligible rated-user "5-star-rated" (and (is-eq rating u5) (>= (get average-rating reputation) u45)))
                (award-badge-if-eligible rated-user "trusted-trader" (and (>= (get total-ratings reputation) u10) (>= (get average-rating reputation) u40)))
                (award-badge-if-eligible rated-user "reputation-master" (is-eq (get reputation-level reputation) REPUTATION-PLATINUM))
                true
            )
            true
        )
        
        (ok true)
    )
)

(define-public (update-rating (rated-user principal) (new-rating uint) (new-feedback (string-ascii 512)))
    (let ((existing-rating (unwrap! (get-user-rating tx-sender rated-user) ERR-RATING-ALREADY-EXISTS)))
        (asserts! (var-get reputation-system-enabled) ERR-REPUTATION-SYSTEM-DISABLED)
        (asserts! (and (>= new-rating MIN-RATING) (<= new-rating MAX-RATING)) ERR-RATING-OUT-OF-RANGE)
        (asserts! (<= (len new-feedback) MAX-FEEDBACK-LENGTH) ERR-FEEDBACK-TOO-LONG)
        
        ;; Update the existing rating
        (map-set user-ratings
            { rater: tx-sender, rated-user: rated-user }
            (merge existing-rating {
                rating: new-rating,
                feedback: new-feedback,
                created-at: burn-block-height
            })
        )
        
        ;; Note: For simplicity, we don't recalculate all reputation stats here
        ;; In a production system, you might want to implement a more complex recalculation
        
        (ok true)
    )
)

(define-public (verify-user (user principal))
    (begin
        (asserts! (is-eq tx-sender (var-get reputation-admin)) ERR-NOT-AUTHORIZED)
        (asserts! (var-get reputation-system-enabled) ERR-REPUTATION-SYSTEM-DISABLED)
        
        (match (get-user-reputation user)
            reputation
            (begin
                (map-set user-reputation
                    { user: user }
                    (merge reputation { is-verified: true })
                )
                (award-badge-if-eligible user "verified-trader" true)
                (ok true)
            )
            ;; If user has no reputation yet, create a basic profile
            (begin
                (map-set user-reputation
                    { user: user }
                    {
                        total-ratings: u0,
                        total-score: u0,
                        average-rating: u0,
                        reputation-level: REPUTATION-NOVICE,
                        positive-feedback-count: u0,
                        negative-feedback-count: u0,
                        neutral-feedback-count: u0,
                        last-rating-received: u0,
                        reputation-points: u0,
                        is-verified: true
                    }
                )
                (award-badge-if-eligible user "verified-trader" true)
                (ok true)
            )
        )
    )
)

(define-public (toggle-reputation-system)
    (begin
        (asserts! (is-eq tx-sender (var-get reputation-admin)) ERR-NOT-AUTHORIZED)
        (var-set reputation-system-enabled (not (var-get reputation-system-enabled)))
        (ok (var-get reputation-system-enabled))
    )
)

(define-public (set-reputation-admin (new-admin principal))
    (begin
        (asserts! (is-eq tx-sender (var-get reputation-admin)) ERR-NOT-AUTHORIZED)
        (var-set reputation-admin new-admin)
        (ok true)
    )
)

(define-public (set-reputation-config (config-key (string-ascii 32)) (config-value uint))
    (begin
        (asserts! (is-eq tx-sender (var-get reputation-admin)) ERR-NOT-AUTHORIZED)
        (map-set reputation-config
            { config-key: config-key }
            {
                config-value: config-value,
                last-updated: burn-block-height
            }
        )
        (ok true)
    )
)

(define-public (bulk-rate-users (ratings-data (list 10 { user: principal, rating: uint, feedback: (string-ascii 256) })))
    (begin
        (asserts! (var-get reputation-system-enabled) ERR-REPUTATION-SYSTEM-DISABLED)
        (ok (len ratings-data))
    )
)

(define-public (get-top-rated-users (limit uint))
    (let ((actual-limit (if (> limit u20) u20 limit)))
        (ok (list))
    )
)
