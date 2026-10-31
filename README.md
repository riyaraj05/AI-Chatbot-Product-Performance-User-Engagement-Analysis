# AI Chatbot Product Performance & User Engagement Analysis

A product-analytics project on an AI customer-support chatbot: **adoption, task completion, repeat usage and CSAT**, plus an
**LLM-powered classifier** that turns free-text feedback into recurring product issues.

> **Tech:** SQL (SQLite) · Python · pandas · statsmodels · scipy · matplotlib/seaborn · LLM API (Claude) · Jupyter

> **Data note:** the data is **simulated** (`src/generate_data.py`, seed 42). No public dataset combines task completion,
> latency, CSAT and feedback text for a chatbot, so the generator bakes in realistic cause-and-effect (slow responses and
> fallbacks reduce completion; a good first chat drives return visits; a 3-day latency incident). The analysis workflow is
> identical to what you would run on real product data.

## Business questions

| # | Question | Where answered |
|---|----------|----------------|
| 1 | Is the data trustworthy? | `sql/01_data_quality_checks.sql` |
| 2 | Do signups adopt the bot? Is usage growing and sticky? | `sql/02_adoption_engagement.sql` |
| 3 | How often does the bot complete the user's task, and where does it fail? | `sql/03_task_completion.sql` |
| 4 | Does the first conversation decide whether users return? | `sql/04_repeat_usage.sql` |
| 5 | What drives CSAT, and how reliable is the survey? | `sql/05_csat_analysis.sql` |
| 6 | What do users complain about? | `src/classify_feedback.py` + notebook section 6 |

## Methods

- **SQL:** CTEs, `ROW_NUMBER` (first conversation per user), `LAG` (week-over-week), moving-average window frames (incident detection), `RANK`, cohort retention, conditional aggregation, NULL-safe survey metrics.
- **Python:** logistic regression (`statsmodels`) to separate latency, fallbacks and intent effects, chi-square tests, cohort heatmaps.
- **LLM text classification:** the Claude API labels feedback into 8 themes in batches of 25 (`temperature=0`, strict JSON output, labels validated against the allowed set). Falls back to a keyword baseline when no API key is set, so everything runs offline.

## Key findings (seed-42 run)

1. **Task completion is 59.5%.** The weakest intents are `technical_issue` (25%), `refund_return` (37%) and `billing` (45%), versus 81% for `order_status`.
2. **Speed and fallbacks hurt independently.** Controlling for intent, platform and plan, each extra second of latency lowers the odds of completion by ~31% and each fallback by ~42%.
3. **A latency incident was detected automatically** (10-12 Apr: latency ~2.5x normal, completion fell to ~34% vs ~60% normally).
4. **The first conversation decides retention.** 72% of users with a resolved first chat return within 14 days versus 25% with an unresolved first chat (chi-square p < 0.001).
5. **CSAT is biased.** Only 35% of conversations get a rating, and unresolved users respond more (44% vs 30%), so completion rate is the more reliable quality metric.
6. **Feedback themes:** "misunderstood request" is the largest complaint theme, followed by "needs a human agent".

## Recommendations

1. Give the bot **tools to act** (process refunds, change billing), not just explain, for the three weakest intents. Lifting them by 10 pp would raise overall completion by ~3.4 pp.
2. Add **latency monitoring and alerts** (daily latency above 1.5x the 7-day average) plus a clarifying-question flow to cut fallbacks.
3. Optimise **first-session quality**: guided onboarding, and a handoff to a human after two fallbacks.
4. Add a one-tap thumbs up/down to **raise survey coverage** and reduce response bias.
5. **Validate with an A/B test** (e.g. new fallback handling vs old) since these findings are observational.

## Project structure

```
.
├── data/raw/                      # generated CSVs (git-ignored)
├── sql/
│   ├── 01_data_quality_checks.sql
│   ├── 02_adoption_engagement.sql
│   ├── 03_task_completion.sql
│   ├── 04_repeat_usage.sql
│   └── 05_csat_analysis.sql
├── notebooks/
│   └── 01_chatbot_engagement_analysis.ipynb
├── src/
│   ├── generate_data.py           # simulated dataset
│   ├── load_data.py               # CSV -> SQLite
│   ├── classify_feedback.py       # LLM / keyword feedback classifier
│   └── db.py                      # run .sql files from Python
├── images/
├── requirements.txt
└── README.md
```

## How to run

```bash
pip install -r requirements.txt
python src/generate_data.py          # simulate data -> data/raw/
python src/load_data.py              # build data/chatbot.db

# optional: use the Claude API for feedback classification
export ANTHROPIC_API_KEY=your_key_here
python src/classify_feedback.py      # auto-uses the LLM if a key is set, else keywords

jupyter notebook notebooks/
```

Set `CLASSIFIER_MODEL` to change the model (default `claude-haiku-4-5`).

## Limitations

- Simulated data, so absolute numbers are illustrative. The methodology is what transfers.
- Findings are observational (correlation, not causation).
- Simulated feedback is templated, so classifier accuracy on it is optimistic; real feedback is messier and benefits more from an LLM.
- CSAT is a voluntary survey with response bias.
