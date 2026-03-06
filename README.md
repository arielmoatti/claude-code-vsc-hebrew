# תיקון עברית (RTL) ל-Claude Code ב-VSCode — גרסה 4

בלי התיקון הזה, עברית מוצגת הפוך בתוסף Claude Code — `םולש` במקום `שלום`.

## הבעיה

ה-CSS של התוסף כולל כלל `unicode-bidi: bidi-override` שכופה כיוון שמאל-לימין על **כל** הטקסט, כולל עברית.

## מה הפתרון עושה

סקריפט Bash שרץ אוטומטית בתחילת כל סשן של Claude Code (דרך [hooks](https://docs.anthropic.com/en/docs/claude-code/hooks)) ועושה שלושה דברים:

1. **מנטרל את הבאג** — מחליף `bidi-override` ב-`normal`
2. **מזריק CSS** — בידוד כיוון per פסקה, בלוקי קוד תמיד LTR, נקודות ברשימות בצד הנכון
3. **מזריק JS חכם** — זיהוי שפה בזמן אמת per פסקה באמצעות MutationObserver

### אלגוריתם הזיהוי (חדש בגרסה 4)

כל פסקה נבדקת בנפרד:

| אות חזקה ראשונה | אחוז עברית | תוצאה |
|---|---|---|
| עברית | לא משנה | **RTL** |
| אנגלית | ≥ 30% עברית | **RTL** |
| אנגלית | < 30% עברית | **LTR** |
| אין אותיות (רק מספרים/אמוג'י) | — | ללא שינוי |

בנוסף, מוזרק **עוגן RLM** (תו U+200F) בתחילת פסקאות RTL — פותר בעיות כיוון כשהילד הראשון מכיל טקסט אנגלי (למשל `<code>` בתוך משפט עברי).

### דוגמאות

```
"שלום עולם"                        → RTL (אות ראשונה עברית)
"Hello world"                      → LTR (אות ראשונה אנגלית, 0% עברית)
"Hello שלום"                       → RTL (אות ראשונה אנגלית, אבל 36% ≥ 30%)
"1.1 Migration: הוספת שדות"         → RTL (אות ראשונה אנגלית, אבל ~50% ≥ 30%)
"🎉 שלום"                          → RTL (דילוג על אמוג'י, אות ראשונה עברית)
```

## התקנה

### התקנה מהירה (הדבקה לתוך Claude Code)

העתיקו את הבלוק הבא והדביקו אותו לתוך Claude Code — הוא יעשה את השאר:

```
התקן את תיקון ה-RTL v4 לעברית ב-Claude Code VSCode extension.
בצע את כל הצעדים הבאים:

שלב 1 — צור תיקיית scripts בתיקיית העבודה הנוכחית (אם לא קיימת).

שלב 2 — הורד את fix-claude-rtl.sh מהכתובת
https://raw.githubusercontent.com/arielmoatti/claude-code-vsc-hebrew/main/fix-claude-rtl.sh
ושמור אותו ב-scripts/fix-claude-rtl.sh

שלב 3 — צור scripts/rtl-mode.conf עם התוכן: full

שלב 4 — הוסף hook לקובץ ~/.claude/settings.json:
{
  "hooks": {
    "SessionStart": [
      {
        "type": "command",
        "command": "bash FULL_PATH/scripts/fix-claude-rtl.sh"
      }
    ]
  }
}
החלף FULL_PATH בנתיב המלא של תיקיית scripts.

שלב 5 — הרץ את הסקריפט פעם ראשונה.

שלב 6 — בקש ממני לעשות Reload Window (Ctrl+Shift+P → Developer: Reload Window).
```

### התקנה ידנית

1. הורידו את `fix-claude-rtl.sh` לתיקיית `scripts/` בפרויקט
2. צרו `scripts/rtl-mode.conf` עם התוכן `full`
3. הוסיפו את ה-hook ל-`~/.claude/settings.json` (ראו למעלה)
4. הריצו `bash scripts/fix-claude-rtl.sh`
5. עשו Reload Window ב-VSCode

## שני מצבים

| מצב | תיאור |
|---|---|
| **full** (ברירת מחדל) | RTL מלא עם זיהוי שפה — עברית מימין, אנגלית משמאל |
| **word** | רק תיקון תווים — מילים בעברית תקינות, בלי שינוי כיוון פסקה |

להחלפת מצב, אמרו לקלוד: *"תחליף RTL ל-word"* או *"תחליף RTL ל-full"*

## איך זה עובד

הסקריפט פוטץ' את קבצי ה-webview של התוסף (`index.css` ו-`index.js`) שנמצאים ב-`~/.vscode/extensions/anthropic.claude-code-*/webview/`.

**פאטץ' CSS:**
- `unicode-bidi: isolate` על כל אלמנטי טקסט (פסקאות, כותרות, פריטי רשימה וכו')
- `unicode-bidi: embed` + `direction: ltr` על בלוקי קוד
- `list-style-position: inside` לפריטי רשימה RTL
- `direction: inherit` על צאצאי בועות הודעה (כדי לנטרל את הכלל הגלובלי `* { direction: ltr }`)

**פאטץ' JS:**
- שני MutationObservers — אחד לתגובות קלוד, אחד להודעות שנשלחו
- זיהוי כיוון per פסקה לפי אלגוריתם first-strong + סף 30%
- Watchdog על הודעות משתמש שמחזיר את הכיוון אם VSCode מאפס אותו

הסקריפט **אידמפוטנטי** — מסיר כל פאטץ' קודם לפני שמחיל, אז בטוח להריץ כמה פעמים. מטפל בכל גרסאות התוסף המותקנות במקביל.

## מגבלות ידועות

- הודעה שמתחילה באנגלית עם פחות מ-30% עברית — כל הבועה תהיה LTR (כל בועת הודעה היא אלמנט אחד)
- התנגשות עם תוספי RTL אחרים (למשל `YechielBy/claude-code-rtl-extension` או `GuyRonnen/rtl-for-vs-code-agents`) — השתמשו רק באחד

## קרדיט

אלגוריתם הזיהוי בגרסה 4 בהשראת [GuyRonnen/rtl-for-vs-code-agents](https://github.com/GuyRonnen/rtl-for-vs-code-agents) (סף 30%, עוגני RLM, `unicode-bidi: isolate`).

## רישיון

MIT
