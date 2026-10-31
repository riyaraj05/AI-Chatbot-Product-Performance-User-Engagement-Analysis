"""
Generate a SIMULATED AI-chatbot interaction dataset (seeded, reproducible).

Why simulated? No public dataset combines task completion, latency, CSAT and free-text
feedback for a chatbot. The generator bakes in realistic cause-and-effect so the analysis
has real patterns to discover:
  * slower responses and more fallbacks -> lower task completion -> lower CSAT
  * billing / refund / technical intents are harder for the bot
  * a successful FIRST conversation strongly increases repeat usage
  * a latency incident (2025-04-10 to 2025-04-12) degrades the product for three days

IMPORTANT: say clearly in your README / interview that the data is simulated.

Usage:  python src/generate_data.py            # writes CSVs to data/raw/
"""
from pathlib import Path

import numpy as np
import pandas as pd

SEED = 42
N_USERS = 8000
START = pd.Timestamp("2025-01-01")
END = pd.Timestamp("2025-06-30 23:59:59")
INCIDENT_DAYS = {pd.Timestamp("2025-04-10").date(), pd.Timestamp("2025-04-11").date(), pd.Timestamp("2025-04-12").date()}

INTENTS = {
    # intent: (share, base_completion_prob, median_latency_ms, mean_turns)
    "order_status":    (0.22, 0.86, 1500, 3.0),
    "how_to":          (0.20, 0.80, 1900, 4.0),
    "product_info":    (0.12, 0.78, 1800, 3.5),
    "account_access":  (0.12, 0.70, 1700, 4.0),
    "billing":         (0.15, 0.62, 2100, 4.5),
    "refund_return":   (0.11, 0.55, 2200, 5.0),
    "technical_issue": (0.08, 0.50, 2900, 6.0),
}

FEEDBACK = {
    "slow_response": [
        "Took forever to reply, I gave up waiting", "Responses are really slow", "The bot is so slow, a human would be faster",
        "Long delays between every message", "Waited a long time for each answer", "too slow, kept loading",
    ],
    "misunderstood_request": [
        "It did not understand what I was asking", "Kept giving me the same irrelevant answer", "Misunderstood my question completely",
        "I rephrased 3 times and it still didn't get it", "Answers had nothing to do with my question", "It keeps saying it doesn't understand",
    ],
    "inaccurate_answer": [
        "The information it gave me was wrong", "Gave incorrect order details", "Answer was outdated and inaccurate",
        "It told me something that turned out to be false", "Wrong policy information, caused confusion",
    ],
    "cannot_perform_action": [
        "It can't actually process my refund, just gives instructions", "Wanted it to change my plan but it can't do anything",
        "Only tells me what to do, never does it for me", "Could not cancel my order through the chat", "No way to complete the request in the chat",
    ],
    "needs_human_agent": [
        "I just want to talk to a real person", "No option to reach a human agent", "Had to start over when I asked for an agent",
        "Please let me speak with a human", "Escalation to support was hard to find",
    ],
    "ui_usability": [
        "The chat window is confusing to use", "Hard to find the chat on mobile", "Buttons are tiny and the layout is cluttered",
        "Chat history disappeared when I refreshed", "Could not attach a screenshot",
    ],
    "positive_feedback": [
        "Quick and helpful, thanks", "Solved my issue in seconds", "Really easy to use", "Great experience, very clear answers",
        "Helpful and fast", "Worked perfectly",
    ],
    "other": [
        "ok", "Not sure what to say", "Meh", "Average experience", "It was fine I guess", "n/a",
    ],
}


def main(out_dir: Path = Path("data/raw")) -> None:
    rng = np.random.default_rng(SEED)
    out_dir.mkdir(parents=True, exist_ok=True)

    # ------------------------------------------------------------- users
    signup_offset = (rng.beta(1.3, 1.0, N_USERS) * 160).astype(int)  # growth: more signups later
    users = pd.DataFrame({
        "user_id": np.arange(1, N_USERS + 1),
        "signup_date": START + pd.to_timedelta(signup_offset, unit="D"),
        "plan": rng.choice(["free", "pro", "enterprise"], N_USERS, p=[0.70, 0.25, 0.05]),
        "platform": rng.choice(["web", "mobile", "slack"], N_USERS, p=[0.55, 0.35, 0.10]),
    })

    intent_names = list(INTENTS)
    intent_p = np.array([INTENTS[k][0] for k in intent_names])

    convs = []
    conv_id = 0

    def make_conversation(user, ts, is_first):
        nonlocal conv_id
        conv_id += 1
        intent = rng.choice(intent_names, p=intent_p)
        _, base_p, med_lat, mean_turns = INTENTS[intent]

        lat = float(rng.lognormal(np.log(med_lat), 0.45))
        if user.platform == "mobile":
            lat *= 1.15
        if ts.date() in INCIDENT_DAYS:
            lat *= 2.6
        lat = max(250.0, lat)

        fallback_mean = 0.25 + 1.6 * (1 - base_p)
        fallbacks = int(rng.poisson(fallback_mean * (1.4 if ts.date() in INCIDENT_DAYS else 1.0)))

        logit = np.log(base_p / (1 - base_p)) - 0.55 * fallbacks - 0.38 * (lat / 1000 - 1.8)
        if user.plan == "enterprise":
            logit += 0.15
        p_resolved = 1 / (1 + np.exp(-logit))
        resolved = bool(rng.random() < p_resolved)

        turns = int(max(1, rng.poisson(mean_turns * (0.8 if resolved else 1.35)) + fallbacks))
        escalated = (not resolved) and bool(rng.random() < 0.45)

        # CSAT survey: only some users answer, unresolved users answer a bit more often
        responded = rng.random() < (0.30 if resolved else 0.45)
        csat = np.nan
        if responded:
            mu = 4.35 if resolved else 2.1
            mu -= 0.25 * max(0.0, lat / 1000 - 2.5)
            csat = int(np.clip(np.round(rng.normal(mu, 0.9)), 1, 5))

        # root cause for free-text feedback (ground truth, used only to evaluate the classifier)
        theme = None
        if responded and rng.random() < (0.6 if csat <= 3 else 0.18):
            if csat >= 4:
                theme = "positive_feedback" if rng.random() < 0.85 else "other"
            else:
                weights = {"slow_response": 0.5 + (3.0 if lat > 3500 else 0.0),
                           "misunderstood_request": 1.0 + 1.6 * fallbacks,
                           "inaccurate_answer": 0.8,
                           "cannot_perform_action": 0.4 + (2.5 if intent in ("refund_return", "billing") else 0.0),
                           "needs_human_agent": 0.5 + (1.5 if escalated else 0.0),
                           "ui_usability": 0.5 + (1.2 if user.platform == "mobile" else 0.0),
                           "other": 0.4}
                keys = list(weights); w = np.array([weights[k] for k in keys]); w = w / w.sum()
                theme = rng.choice(keys, p=w)
        feedback_text = None
        if theme:
            feedback_text = str(rng.choice(FEEDBACK[theme]))
            if rng.random() < 0.12:
                feedback_text = feedback_text.lower()
            if rng.random() < 0.08:
                feedback_text += " !!"

        return {
            "conversation_id": conv_id, "user_id": user.user_id, "started_at": ts,
            "intent": intent, "num_turns": turns, "fallback_count": fallbacks,
            "avg_response_latency_ms": round(lat),
            "resolved": int(resolved), "escalated_to_human": int(escalated),
            "csat_score": csat, "feedback_text": feedback_text, "_theme": theme,
        }

    for user in users.itertuples():
        # ---- activation: did the user ever start a chat?
        activated = rng.random() < 0.84
        if not activated:
            continue
        first_ts = user.signup_date + pd.Timedelta(days=int(rng.choice([0, 0, 0, 1, 1, 2, 3, 5])),
                                                   hours=int(rng.integers(7, 23)), minutes=int(rng.integers(0, 60)))
        if first_ts > END:
            continue
        first = make_conversation(user, first_ts, True)
        convs.append(first)

        # ---- repeat usage depends strongly on the first experience
        lam = 0.30 + (1.3 if first["resolved"] else 0.0) - (0.35 if first["avg_response_latency_ms"] > 3500 else 0.0)
        lam *= {"free": 1.0, "pro": 1.35, "enterprise": 1.7}[user.plan]
        lam = max(lam, 0.1)
        n_more = int(rng.poisson(lam * 1.3))
        ts = first_ts
        for _ in range(n_more):
            ts = ts + pd.Timedelta(days=float(rng.exponential(8.0)) + 0.3)
            if ts > END:
                break
            convs.append(make_conversation(user, ts, False))

    conv = pd.DataFrame(convs)
    conv["started_at"] = pd.to_datetime(conv["started_at"]).dt.strftime("%Y-%m-%d %H:%M:%S")

    feedback = conv.loc[conv["feedback_text"].notna(), ["conversation_id", "feedback_text"]].copy()
    truth = conv.loc[conv["_theme"].notna(), ["conversation_id", "_theme"]].rename(columns={"_theme": "true_theme"})
    conv = conv.drop(columns=["feedback_text", "_theme"])
    users["signup_date"] = users["signup_date"].dt.strftime("%Y-%m-%d")

    users.to_csv(out_dir / "users.csv", index=False)
    conv.to_csv(out_dir / "conversations.csv", index=False)
    feedback.to_csv(out_dir / "feedback.csv", index=False)
    truth.to_csv(out_dir / "feedback_ground_truth.csv", index=False)
    print(f"users={len(users):,}  conversations={len(conv):,}  feedback={len(feedback):,}")
    print(f"written to {out_dir}/")


if __name__ == "__main__":
    main()
