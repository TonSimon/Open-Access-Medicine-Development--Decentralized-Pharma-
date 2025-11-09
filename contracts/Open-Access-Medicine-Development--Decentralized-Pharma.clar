(define-constant ERR-UNAUTHORIZED (err u100))
(define-constant ERR-INVALID-MILESTONE (err u101))
(define-constant ERR-INSUFFICIENT-FUNDS (err u102))
(define-constant ERR-PROJECT-NOT-FOUND (err u103))
(define-constant ERR-MILESTONE-COMPLETED (err u104))
(define-constant ERR-VOTING-PERIOD-ENDED (err u105))
(define-constant ERR-ALREADY-VOTED (err u106))
(define-constant ERR-PROPOSAL-NOT-FOUND (err u107))

(define-data-var next-project-id uint u1)
(define-data-var next-proposal-id uint u1)

(define-map research-projects
  { project-id: uint }
  {
    creator: principal,
    title: (string-ascii 256),
    description: (string-ascii 1024),
    target-funding: uint,
    current-funding: uint,
    milestone-count: uint,
    completed-milestones: uint,
    ip-token-supply: uint,
    total-rating-sum: uint,
    rating-count: uint,
    active: bool
  }
)

(define-map project-milestones
  { project-id: uint, milestone-id: uint }
  {
    description: (string-ascii 512),
    funding-required: uint,
    completed: bool,
    completion-timestamp: (optional uint)
  }
)

(define-map project-funders
  { project-id: uint, funder: principal }
  { amount-contributed: uint, ip-tokens-owned: uint }
)

(define-map governance-proposals
  { proposal-id: uint }
  {
    proposer: principal,
    project-id: uint,
    proposal-type: (string-ascii 64),
    description: (string-ascii 512),
    votes-for: uint,
    votes-against: uint,
    voting-deadline: uint,
    executed: bool
  }
)

(define-map proposal-votes
  { proposal-id: uint, voter: principal }
  { vote: bool, voting-power: uint }
)

(define-map clinical-trial-data
  { project-id: uint, trial-phase: uint }
  {
    data-hash: (buff 32),
    participant-count: uint,
    success-rate: uint,
    timestamp: uint,
    verified: bool,
    votes-for: uint,
    votes-against: uint,
    voting-deadline: uint
  }
)

(define-map clinical-data-votes
  { project-id: uint, trial-phase: uint, voter: principal }
  { vote: bool, voting-power: uint }
)

(define-public (create-research-project 
  (title (string-ascii 256))
  (description (string-ascii 1024))
  (target-funding uint)
  )
  (let ((project-id (var-get next-project-id)))
    (asserts! (> target-funding u0) ERR-INVALID-MILESTONE)
    
    (map-set research-projects
      { project-id: project-id }
      {
        creator: tx-sender,
        title: title,
        description: description,
        target-funding: target-funding,
        current-funding: u0,
        milestone-count: u0,
        completed-milestones: u0,
        ip-token-supply: (* target-funding u100),
        total-rating-sum: u0,
        rating-count: u0,
        active: true
      }
    )
    
    (var-set next-project-id (+ project-id u1))
    (ok project-id)
  )
)

(define-public (add-milestone 
  (project-id uint)
  (description (string-ascii 512))
  (funding-required uint))
  (let ((project (unwrap! (map-get? research-projects { project-id: project-id }) ERR-PROJECT-NOT-FOUND))
        (milestone-id (get milestone-count project)))
    
    (asserts! (is-eq tx-sender (get creator project)) ERR-UNAUTHORIZED)
    
    (map-set project-milestones
      { project-id: project-id, milestone-id: milestone-id }
      {
        description: description,
        funding-required: funding-required,
        completed: false,
        completion-timestamp: none
      }
    )
    
    (map-set research-projects
      { project-id: project-id }
      (merge project { milestone-count: (+ milestone-id u1) })
    )
    
    (ok milestone-id)
  )
)

(define-public (contribute-funding (project-id uint) (amount uint))
  (let ((project (unwrap! (map-get? research-projects { project-id: project-id }) ERR-PROJECT-NOT-FOUND))
        (existing-contribution (default-to { amount-contributed: u0, ip-tokens-owned: u0 }
                                           (map-get? project-funders { project-id: project-id, funder: tx-sender })))
        (ip-tokens-earned (* amount u100)))
    
    (asserts! (get active project) ERR-PROJECT-NOT-FOUND)
    (asserts! (>= (stx-get-balance tx-sender) amount) ERR-INSUFFICIENT-FUNDS)
    
    (try! (stx-transfer? amount tx-sender (as-contract tx-sender)))
    
    (map-set research-projects
      { project-id: project-id }
      (merge project { current-funding: (+ (get current-funding project) amount) })
    )
    
    (map-set project-funders
      { project-id: project-id, funder: tx-sender }
      {
        amount-contributed: (+ (get amount-contributed existing-contribution) amount),
        ip-tokens-owned: (+ (get ip-tokens-owned existing-contribution) ip-tokens-earned)
      }
    )
    
    (ok ip-tokens-earned)
  )
)

(define-public (complete-milestone (project-id uint) (milestone-id uint))
  (let ((project (unwrap! (map-get? research-projects { project-id: project-id }) ERR-PROJECT-NOT-FOUND))
        (milestone (unwrap! (map-get? project-milestones { project-id: project-id, milestone-id: milestone-id }) ERR-INVALID-MILESTONE)))
    
    (asserts! (is-eq tx-sender (get creator project)) ERR-UNAUTHORIZED)
    (asserts! (not (get completed milestone)) ERR-MILESTONE-COMPLETED)
    
    (map-set project-milestones
      { project-id: project-id, milestone-id: milestone-id }
      (merge milestone { 
        completed: true, 
        completion-timestamp: (some stacks-block-height) 
      })
    )
    
    (map-set research-projects
      { project-id: project-id }
      (merge project { completed-milestones: (+ (get completed-milestones project) u1) })
    )
    
    (try! (as-contract (stx-transfer? (get funding-required milestone) tx-sender (get creator project))))
    (ok true)
  )
)

(define-public (submit-clinical-data
  (project-id uint)
  (trial-phase uint)
  (data-hash (buff 32))
  (participant-count uint)
  (success-rate uint)
  (voting-period uint))
  (let ((project (unwrap! (map-get? research-projects { project-id: project-id }) ERR-PROJECT-NOT-FOUND)))

    (asserts! (is-eq tx-sender (get creator project)) ERR-UNAUTHORIZED)
    (asserts! (<= success-rate u100) ERR-INVALID-MILESTONE)

    (map-set clinical-trial-data
      { project-id: project-id, trial-phase: trial-phase }
      {
        data-hash: data-hash,
        participant-count: participant-count,
        success-rate: success-rate,
        timestamp: stacks-block-height,
        verified: false,
        votes-for: u0,
        votes-against: u0,
        voting-deadline: (+ stacks-block-height voting-period)
      }
    )

    (ok true)
  )
)

(define-public (create-governance-proposal
  (project-id uint)
  (proposal-type (string-ascii 64))
  (description (string-ascii 512))
  (voting-period uint))
  (let ((proposal-id (var-get next-proposal-id))
        (project (unwrap! (map-get? research-projects { project-id: project-id }) ERR-PROJECT-NOT-FOUND)))
    
    (map-set governance-proposals
      { proposal-id: proposal-id }
      {
        proposer: tx-sender,
        project-id: project-id,
        proposal-type: proposal-type,
        description: description,
        votes-for: u0,
        votes-against: u0,
        voting-deadline: (+ stacks-block-height voting-period),
        executed: false
      }
    )
    
    (var-set next-proposal-id (+ proposal-id u1))
    (ok proposal-id)
  )
)

(define-public (vote-on-proposal (proposal-id uint) (vote bool))
  (let ((proposal (unwrap! (map-get? governance-proposals { proposal-id: proposal-id }) ERR-PROPOSAL-NOT-FOUND))
        (project-id (get project-id proposal))
        (voter-stake (default-to { amount-contributed: u0, ip-tokens-owned: u0 }
                                 (map-get? project-funders { project-id: project-id, funder: tx-sender })))
        (voting-power (get ip-tokens-owned voter-stake)))
    
    (asserts! (> voting-power u0) ERR-UNAUTHORIZED)
    (asserts! (< stacks-block-height (get voting-deadline proposal)) ERR-VOTING-PERIOD-ENDED)
    (asserts! (is-none (map-get? proposal-votes { proposal-id: proposal-id, voter: tx-sender })) ERR-ALREADY-VOTED)
    
    (map-set proposal-votes
      { proposal-id: proposal-id, voter: tx-sender }
      { vote: vote, voting-power: voting-power }
    )
    
    (if vote
      (map-set governance-proposals
        { proposal-id: proposal-id }
        (merge proposal { votes-for: (+ (get votes-for proposal) voting-power) }))
      (map-set governance-proposals
        { proposal-id: proposal-id }
        (merge proposal { votes-against: (+ (get votes-against proposal) voting-power) }))
    )
    
    (ok true)
  )
)

(define-public (vote-on-clinical-data (project-id uint) (trial-phase uint) (vote bool))
  (let ((trial-data (unwrap! (map-get? clinical-trial-data { project-id: project-id, trial-phase: trial-phase }) ERR-PROJECT-NOT-FOUND))
        (voter-stake (default-to { amount-contributed: u0, ip-tokens-owned: u0 }
                                 (map-get? project-funders { project-id: project-id, funder: tx-sender })))
        (voting-power (get ip-tokens-owned voter-stake)))

    (asserts! (> voting-power u0) ERR-UNAUTHORIZED)
    (asserts! (< stacks-block-height (get voting-deadline trial-data)) ERR-VOTING-PERIOD-ENDED)
    (asserts! (is-none (map-get? clinical-data-votes { project-id: project-id, trial-phase: trial-phase, voter: tx-sender })) ERR-ALREADY-VOTED)

    (map-set clinical-data-votes
      { project-id: project-id, trial-phase: trial-phase, voter: tx-sender }
      { vote: vote, voting-power: voting-power }
    )

    (if vote
      (map-set clinical-trial-data
        { project-id: project-id, trial-phase: trial-phase }
        (merge trial-data { votes-for: (+ (get votes-for trial-data) voting-power) }))
      (map-set clinical-trial-data
        { project-id: project-id, trial-phase: trial-phase }
        (merge trial-data { votes-against: (+ (get votes-against trial-data) voting-power) }))
    )

    (ok true)
  )
)

(define-public (finalize-clinical-data-verification (project-id uint) (trial-phase uint))
  (let ((trial-data (unwrap! (map-get? clinical-trial-data { project-id: project-id, trial-phase: trial-phase }) ERR-PROJECT-NOT-FOUND)))

    (asserts! (>= stacks-block-height (get voting-deadline trial-data)) ERR-VOTING-PERIOD-ENDED)
    (asserts! (> (+ (get votes-for trial-data) (get votes-against trial-data)) u0) ERR-INVALID-MILESTONE)

    (if (> (get votes-for trial-data) (get votes-against trial-data))
      (map-set clinical-trial-data
        { project-id: project-id, trial-phase: trial-phase }
        (merge trial-data { verified: true }))
      false
    )

    (ok true)
  )
)

(define-read-only (get-project-info (project-id uint))
  (map-get? research-projects { project-id: project-id })
)

(define-read-only (get-milestone-info (project-id uint) (milestone-id uint))
  (map-get? project-milestones { project-id: project-id, milestone-id: milestone-id })
)

(define-read-only (get-funder-stake (project-id uint) (funder principal))
  (map-get? project-funders { project-id: project-id, funder: funder })
)

(define-read-only (get-proposal-info (proposal-id uint))
  (map-get? governance-proposals { proposal-id: proposal-id })
)

(define-read-only (get-clinical-data (project-id uint) (trial-phase uint))
  (map-get? clinical-trial-data { project-id: project-id, trial-phase: trial-phase })
)

(define-read-only (calculate-ip-ownership (project-id uint) (funder principal))
  (let ((funder-data (unwrap! (map-get? project-funders { project-id: project-id, funder: funder }) (err u0)))
        (project (unwrap! (map-get? research-projects { project-id: project-id }) (err u0))))
    (ok (/ (* (get ip-tokens-owned funder-data) u10000) (get ip-token-supply project)))
  )
)

(define-read-only (get-project-progress (project-id uint))
  (let ((project (unwrap! (map-get? research-projects { project-id: project-id }) (err u0))))
    (ok {
      funding-progress: (/ (* (get current-funding project) u100) (get target-funding project)),
      milestone-progress: (/ (* (get completed-milestones project) u100) (get milestone-count project))
    })
  )
)

(define-public (withdraw-milestone-funds (project-id uint) (milestone-id uint))
  (let ((project (unwrap! (map-get? research-projects { project-id: project-id }) ERR-PROJECT-NOT-FOUND))
        (milestone (unwrap! (map-get? project-milestones { project-id: project-id, milestone-id: milestone-id }) ERR-INVALID-MILESTONE)))
    
    (asserts! (is-eq tx-sender (get creator project)) ERR-UNAUTHORIZED)
    (asserts! (get completed milestone) ERR-INVALID-MILESTONE)
    
    (as-contract (stx-transfer? (get funding-required milestone) tx-sender (get creator project)))
  )
)

(define-public (emergency-pause-project (project-id uint))
  (let ((project (unwrap! (map-get? research-projects { project-id: project-id }) ERR-PROJECT-NOT-FOUND)))
    
    (asserts! (is-eq tx-sender (get creator project)) ERR-UNAUTHORIZED)
    
    (map-set research-projects
      { project-id: project-id }
      (merge project { active: false })
    )
    
    (ok true)
  )
)

(define-public (rate-project (project-id uint) (rating uint))
  (let ((project (unwrap! (map-get? research-projects { project-id: project-id }) ERR-PROJECT-NOT-FOUND))
        (funder-data (unwrap! (map-get? project-funders { project-id: project-id, funder: tx-sender }) ERR-UNAUTHORIZED)))
    (asserts! (and (>= rating u1) (<= rating u5)) ERR-INVALID-MILESTONE)
    (asserts! (> (get amount-contributed funder-data) u0) ERR-UNAUTHORIZED)
    (asserts! (not (get active project)) ERR-PROJECT-NOT-FOUND)
    (map-set research-projects
      { project-id: project-id }
      (merge project {
        total-rating-sum: (+ (get total-rating-sum project) rating),
        rating-count: (+ (get rating-count project) u1)
      })
    )
    (ok true)
  )
)

(define-public (transfer-ip-tokens (project-id uint) (recipient principal) (amount uint))
  (let ((sender-data (unwrap! (map-get? project-funders { project-id: project-id, funder: tx-sender }) ERR-UNAUTHORIZED))
        (recipient-data (default-to { amount-contributed: u0, ip-tokens-owned: u0 } (map-get? project-funders { project-id: project-id, funder: recipient }))))
    (asserts! (>= (get ip-tokens-owned sender-data) amount) ERR-INSUFFICIENT-FUNDS)
    (asserts! (not (is-eq tx-sender recipient)) ERR-INVALID-MILESTONE)
    (map-set project-funders
      { project-id: project-id, funder: tx-sender }
      (merge sender-data { ip-tokens-owned: (- (get ip-tokens-owned sender-data) amount) })
    )
    (map-set project-funders
      { project-id: project-id, funder: recipient }
      (merge recipient-data { ip-tokens-owned: (+ (get ip-tokens-owned recipient-data) amount) })
    )
    (ok true)
  )
)

(define-read-only (get-project-average-rating (project-id uint))
  (let ((project (unwrap! (map-get? research-projects { project-id: project-id }) (err u0))))
    (if (> (get rating-count project) u0)
      (ok (/ (* (get total-rating-sum project) u100) (get rating-count project)))
      (err u0)
    )
  )
)
