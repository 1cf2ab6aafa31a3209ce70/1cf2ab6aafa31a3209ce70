# ADR-010 — Blocky Marty rules

**Date:** 2026-10-21. **Status:** Accepted. Epic 09A's first task records the complete title's rules before any shared genre code. This record extends the Epic 07 reference slice's rules. The project owner chose fixed columns, unlimited undo and the name Blocky Marty, and asked for the scoring rule to follow a review of published scoring practice and research; that review is under [Scoring review](#scoring-review).

## Context

The reference slice ([BlockRules.swift](../../Games/BlockContent/Sources/BlockContent/BlockRules.swift), [content record](../../Games/BlockTitle/CONTENT.md)) clears a group of two or more orthogonally connected blocks of one kind, lets the blocks above fall, wins on an empty board and ends without progress when no group of two remains. Each clear of n blocks scores n × (n − 1). Two hand-made boards ship under the working title Block Match.

Constraints the complete title keeps:

- **Accessible input.** Every move is possible from a standard button that names its block by row, column and kind ([accessibility checklist](../../docs/accessibility-checklist.md) item 7), by touch on the board, and from a keyboard. There is no drag, timing or multi-finger input.
- **Determinism.** A level, its seed and an input fixture fix the outcome; animation never advances the rules ([ADR-007](ADR-007-module-contract-v1.md)).
- **No dead ends.** Every shipped level is clearable, and the validator proves it before the level ships.
- **Distinct from the tile title.** Epic 09B documents its own rules against these.
- **Saves.** `SaveProgress` already records completed levels, unlocks and a best score per level, and keeps the higher score.

## Decision

1. **Name.** The title is **Blocky Marty**. The name is user-facing only: the title ID `block-match`, the `BlockTitle` target, the bundle identifier and the save namespace stay as they are, because the ID names the save namespace and the catalog.
2. **Board.** A rectangular grid from 3 × 3 to 8 × 8, with two to four block kinds per level. Each kind keeps its own color, white mark and name: Coral circle, Teal square, Gold triangle, Violet diamond.
3. **Move.** Selecting any block of a group of two or more orthogonally connected blocks of one kind clears the whole group. Blocks above each cleared cell fall straight down. A single block cannot be selected; selecting it changes nothing.
4. **Columns stay put.** An emptied column stays empty; columns never shift sideways. With fixed columns a move changes only the rows of the blocks above the gap, so a VoiceOver or keyboard player keeps the map they built from the block names.
5. **End states.** A level is cleared when the board is empty; the shell's success page shows the score and the level's best and offers Next board and Back to menu. A board is stuck when blocks remain and no group of two does. Stuck is a state of the play page, not an outcome: the page says "No moves left", announces it to VoiceOver, and offers Undo and End board. End board, available throughout play, ends the play as a failure; the failure page offers Try again and Back to menu and records nothing. Keeping a stuck board on the play page puts Undo next to the board it changes and needs no third action on the shared result page.
6. **Undo.** Unlimited undo within one play: each undo restores the board and score before the last move, on a stuck board too. Undo is an input in the replay fixtures, so a recorded play still reproduces. A mistaken tap, a switch or keyboard slip, or an exploratory move costs nothing, and there is no timer to protect.
7. **Scoring.** Each clear of n blocks scores n × (n − 1): every block scores one point for each other block in its group. The score counts only when the board is cleared: the success page shows it with the level's best, and only a cleared play can set the best. An ended play records nothing. There is no clear bonus, remaining-block penalty, star rating, par score or timer, undo costs nothing, and progress never depends on the score. The [scoring review](#scoring-review) gives the reasons.
8. **Progression.** Thirty curated levels in three chapters of ten: chapter 1 has 3 × 3 to 5 × 5 boards with two kinds (Coral circle, Teal square), chapter 2 has 5 × 5 to 7 × 7 boards adding Gold triangle, chapter 3 has 6 × 6 to 8 × 8 boards adding Violet diamond. Each level unlocks the next. Play opens the first uncompleted level in catalog order, and Next board does the same after a clear. Once every level is complete, Next board opens the level after the one just cleared, the last level leading back to the first, and Play after a relaunch opens the first level. Every level stays replayable. A level list is shared shell work and stays out of 09A.
9. **Teaching.** The first three levels carry one line of instruction each on the play page: select a group; blocks fall and columns stay; a block with no partner stays, and Undo takes back a move. There is no modal tutorial.
10. **Level authoring.** Levels are written by hand or generated from a seed by reverse construction: start from an empty board and insert groups that the forward move would clear exactly, so every generated board has a known clearing sequence. Each level file carries one clearing sequence, and the validator replays it; a level whose sequence does not clear its board is rejected. Generation runs at authoring time only, from a plan file that fixes every level's size, kinds and difficulty band; the app ships fixed boards.

## Scoring review

The owner asked for the scoring rule to rest on a review of practice and research rather than on the reference slice's choice. Four candidates were compared: n × (n − 1), SameGame's (n − 2)² with a clear bonus, moves only, and no score.

**Practice in this genre.**

- SameGame's common rule scores (n − 2)² per group and adds 1,000 points for an empty board ([CodinGame SameGame rules](https://www.codingame.com/multiplayer/optimization/samegame)); on the 15 × 15, five-color research test set the bonus is about 20–50% of a final score ([Klein 2015](https://www.diva-portal.org/smash/get/diva2:813153/FULLTEXT01.pdf)). Some versions subtract points for blocks left at the end ([SameGame](https://en.wikipedia.org/wiki/SameGame)).
- Jawbreaker and Bubble Breaker score n × (n − 1) ([Jawbreaker](https://en.wikipedia.org/wiki/Jawbreaker_(Windows_Mobile_game))).
- Versions without a goal score, such as Bonkers and SameGameBros, make clearing the level the goal ([SameGame](https://en.wikipedia.org/wiki/SameGame)).

**Research on scores and motivation.**

- In a controlled experiment, points, levels and leaderboards increased how much participants did but did not significantly change intrinsic motivation or perceived competence ([Mekler et al. 2017](https://www.sciencedirect.com/science/article/pii/S0747563215301229)). A score is a low-risk addition, not the reason to play.
- Progression elements, beating one's own record among them, did not raise persistence across tasks; their effect depended on the task, and for tasks people already enjoy it was difficulty progression that raised motivation ([The Motivational Power of Levels and High Scores](https://dl.acm.org/doi/10.1145/3725892)). The curated level curve carries progression; a best score is an optional extra.
- Players' effort rises with difficulty while a task stays feasible and drops sharply once it is not ([Strojny et al. 2023](https://pmc.ncbi.nlm.nih.gov/articles/PMC10004480/)). Progress must never wait on a score target a player cannot reach.
- A design argument, not a study: a binary goal supports planning better than an open-ended score ([Burgun 2017](https://keithburgun.net/against-score-systems-and-for-success-and-failure/)). Clearing the board stays the goal; the score only ranks clears.

**Analysis for this title.**

- (n − 2)² scores nothing for a pair and 1 for three. Chapter 1's boards (at most 25 blocks, two kinds) clear mostly in groups of two to four, so most first-chapter moves would score 0 and the score would say little. The 1,000-point bonus is sized for 225-block boards; on the 6-block first board, cleared in three pairs, it would be the whole score, and choosing a constant per size is tuning without evidence.
- n × (n − 1) scores every legal move, still grows faster than the group, so building larger groups pays at every board size, and it explains in one sentence.
- Under any per-group score, a play can earn more by forming one large group and stranding a block than by clearing the board. On the second board, `intro-02`, clearing the group of five early scores 26 and strands a block, while every clearing line scores 20. If such a play counted, the score would reward abandoning the goal. Counting the score only for a cleared board removes the conflict without a tuned bonus or penalty.
- The score does rank clears. On the shipped boards, the best of 1,000 random clearing plays scores up to 3.5 times the recorded clearing line (`intro-04`: 56 against 16; `final-10`: 376 against 166), so a planned order of clears earns a visibly better result.
- Moves only also rewards larger groups, but needs a fewest-moves best that `SaveProgress` does not keep, and it adds nothing the score lacks. No score at all gives a returning player no reason to replay a cleared level.
- Unlimited undo lets a player reach a best score by trial. The best is personal and local, with no leaderboard, so nothing depends on it being hard to earn.

## Consequences

- `BlockGame` gains an undo history and `BlockAction` an undo case; replay fixtures and their tests cover undo.
- The module keeps a stuck board on its play page with Undo and End board, and posts a VoiceOver announcement when the board becomes stuck.
- Two additive, defaulted contract members let a title show the result: `ShellPresentation.successRetryLabel` (the success page's continue label, defaulting to `retryLabel`) and `ModuleSession.resultSummary` (a line for the result page, defaulting to none). Every existing registration compiles and behaves unchanged, so `contractVersion` stays 1; the contract tests cover both members.
- The level payload gains its chapter and its clearing sequence. `BlockCatalog` validation adds the chapter's size and kind ranges, the unlock chain, distinct boards and seeds, and the replay of each clearing sequence.
- An authoring-only generator target and its plan file produce the generated levels; the app does not link it.
- The content record, release metadata and accessibility record carry the name Blocky Marty.
