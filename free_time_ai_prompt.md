# Free Time AI Prompt

## Prompt: Optimal Reading Time Estimation (`estimateBestTime`)

### System Prompt

```
You are a scheduling assistant. Return ONLY a single-line valid JSON object. No markdown. No explanation outside JSON.
```

### User Prompt Template

```
Estimate the optimal reading time for a post with these details:

Category: $category
Complexity: $complexity
Importance window: $importance (Day = same day, Week = within 7 days, Month = within 30 days)
Current time: $currentTime
Deadline: $maxTime
User free time slots: $userFreeTimesJson
Already scheduled reminders: $pendingRemindersJson

Scheduling rules (apply in this priority order):
1. Time MUST be after $currentTime
2. Time MUST be before $maxTime
3. Avoid overlapping with already scheduled reminders
4. Prefer times that fall within user free time slots
5. Apply importance-based spacing:
   - Day: 3–8 hours from now
   - Week: 1–4 days from now, prefer evening or morning slots
   - Month: 7–20 days from now, prefer weekends or user free slots
6. For complex content, prefer morning hours (8–11 AM) when focus is high
7. For entertainment/social, prefer evening (7–10 PM)

Return only with ALL THREE languages:
{"best_time": "YYYY-MM-DD HH:MM:SS", "explanation": "Reason in English | Reason in Arabic | Reason in French"}
```

### Mock Data Example (Month Importance)

```json
{
  "category": "Productivity",
  "complexity": "Medium",
  "importance": "Month",
  "currentTime": "2026-01-15T10:00:00.000Z",
  "maxTime": "2026-02-14T10:00:00.000Z",
  "userFreeTimesJson": [
    {"day": "sunday", "start": "10:00", "end": "13:00"},
    {"day": "saturday", "start": "15:00", "end": "19:00"}
  ],
  "pendingRemindersJson": [
    {"scheduled_at": "2026-01-20T14:00:00.000Z", "opened": false},
    {"scheduled_at": "2026-02-01T09:00:00.000Z", "opened": false}
  ]
}
```

### Expected Response

```json
{"best_time": "2026-02-08T10:00:00", "explanation": "Weekend free slot within month window | فترة الفراغ في عطلة نهاية الأسبوع خلال نافذة الشهر | Créneau libre du week-end dans la fenêtre mensuelle"}
```
