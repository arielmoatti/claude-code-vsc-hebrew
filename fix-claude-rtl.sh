#!/bin/bash
# ── Ensure common binaries are on PATH ────────────────────────────────────
# The SessionStart hook on Windows can invoke bash with a minimal PATH that
# misses curl / node. Add Git-Bash + Node defaults so auto-update works.
for d in "/c/Program Files/Git/usr/bin" "/c/Program Files/Git/mingw64/bin" "/c/Program Files/nodejs" "/usr/bin"; do
  [ -d "$d" ] && case ":$PATH:" in *":$d:"*);; *) PATH="$PATH:$d";; esac
done
export PATH

# ── Changelog (most recent first) ─────────────────────────────────────────
# Single source of truth for version + notes. To release: prepend ONE entry to
# all three arrays. VERSION/UPDATE_NOTE derive from the newest entry, and every
# bump triggers auto-update. The in-webview banner shows only the last 3 entries
# flagged MAJOR=1 (substantial, user-facing fixes); cosmetic/meta tweaks
# (MAJOR=0) still bump the version but stay OUT of the banner. Keep notes free of
# " \ | &  - ASCII apostrophes are auto-swapped to U+2019 so they can't break
# the JS strings.
# Notes are benefit-only and capped at 3 rendered lines - see PROJECTS.md.
COMPATIBLE_EXT_VERSION="2.1.252"
CHANGELOG_VERS=(  "1.15.0" "1.14.1" "1.14.0" "1.13.0" "1.12.0" "1.11.0" "1.10.0" "1.9.0" "1.8.0" "1.7.0" "1.6.0" "1.5.2" "1.5.1" "1.5.0" "1.4.0" "1.3.0" "1.2.0" "1.1.0" )
CHANGELOG_MAJOR=( "1"      "0"      "1"      "1"      "0"      "1"      "0"      "1"     "0"     "0"     "0"     "0"     "0"     "1"     "1"     "1"     "1"     "1"     )
CHANGELOG_NOTES=(
  "מספר שבא אחרי מילה בעיצוב קוד כבר לא קופץ למקום אחר בשורה."
  "גלילה ומיקום הסמן בחלונית הפרומפט תקינים גם בפרומפט ארוך."
  "שורה שמתחילה במילה אנגלית בתוך פרומפט עברי כבר לא קופצת שמאלה."
  "שורות הסיכום האפורות של החשיבה (summarized) מתיישרות לימין כמו כל השאר."
  "חבילת העברית מתקינה את עצמה גם ב-Cursor וב-Antigravity, בנוסף לכל טעמי VSCode."
  "שתי החבילות נטענות יחד באמינות, בלי כמה Reload. וקובץ ההגדרות שלכם כבר לא בסכנת דריסה."
  "לחיצה על X בבאנר סוגרת אותו סופית, גם בפתיחת חלון חדש."
  "עדכונים מגיעים אליכם תוך דקות במקום יממה, עם הודעה בצ'אט כשצריך Reload."
  "גרסת חבילת העברית מוצגת בשורת הגרסה של חבילת ה-UI."
  "תווי כיווניות שנכתבו בטעות לתוך הצ'אט כבר לא מופיעים על המסך. קוד אמיתי לא מושפע."
  "התיקון חל על כל סוגי VS Code, כולל Insiders ו-Remote SSH."
  "פסקה או רשימה באנגלית עם מילים עבריות בודדות כבר לא נדחפת לימין."
  "פסקה עברית עם קוד מודגש באנגלית מתיישרת לימין כמו כל השאר."
  "פריט אנגלי בתוך רשימה עברית מתיישר נכון גם כשיש רווח בין הפריטים."
  "פריט שמתחיל באנגלית בתוך רשימה עברית מתיישר לימין עם שאר הרשימה."
  "הודעות עדכון מופיעות כבאנר בתוך הצ'אט."
  "אתחול הצ'אט כבר לא נתקע אחרי שינה."
  "ההזרקה נטענת מיד ואמינה אחרי שינה או פתיחה מחדש."
)
VERSION="${CHANGELOG_VERS[0]}"
UPDATE_NOTE="${CHANGELOG_NOTES[0]}"

# Build a JS array literal of the last 3 MAJOR entries for the banner.
# Apostrophes -> U+2019 so the single-quoted JS strings can't break; notes hold
# no  " \ | &  so this is safe as a sed replacement string.
CHANGELOG_JS="["; _sep=""; _shown=0
for _i in "${!CHANGELOG_VERS[@]}"; do
  [ "$_shown" -ge 3 ] && break
  [ "${CHANGELOG_MAJOR[$_i]}" = "1" ] || continue
  _v="${CHANGELOG_VERS[$_i]}"; _n="${CHANGELOG_NOTES[$_i]//\'/’}"
  CHANGELOG_JS="$CHANGELOG_JS$_sep{v:'$_v',n:'$_n'}"; _sep=","; _shown=$((_shown+1))
done
CHANGELOG_JS="$CHANGELOG_JS]"
REMOTE_BASE_URL="https://raw.githubusercontent.com/arielmoatti/claude-code-vsc-hebrew/main"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONF_FILE="$SCRIPT_DIR/rtl-mode.conf"
CSS_PATCH_START="/* Claude RTL Patch Start */"
CSS_PATCH_END="/* Claude RTL Patch End */"
JS_PATCH_START="/* Claude RTL JS Start */"
JS_PATCH_END="/* Claude RTL JS End */"

# Mode: first line of rtl-mode.conf ('full' or 'word'). CLI arg overrides.
MODE=""
if [ -n "$1" ]; then
  MODE="$1"
  # Preserve any extra lines (e.g. auto_update=false) when writing mode
  if [ -f "$CONF_FILE" ]; then
    extras="$(sed -n '2,$p' "$CONF_FILE")"
    { echo "$MODE"; [ -n "$extras" ] && echo "$extras"; } > "$CONF_FILE"
  else
    echo "$MODE" > "$CONF_FILE"
  fi
elif [ -f "$CONF_FILE" ]; then
  MODE="$(head -1 "$CONF_FILE" | tr -d '[:space:]')"
fi
if [ "$MODE" != "word" ] && [ "$MODE" != "full" ]; then
  MODE="full"
fi

# Read auto-update flag (default: true). Kill-switch for pinning current version.
AUTO_UPDATE="true"
if [ -f "$CONF_FILE" ]; then
  val="$(grep '^auto_update=' "$CONF_FILE" | cut -d= -f2-)"
  [ -n "$val" ] && AUTO_UPDATE="$val"
fi

# ── Signature for the fast path ───────────────────────────────────────
# Short hash of THIS script + patch-plan-rtl.js + the MODE that affects output.
# It is written as a marker line into each patched file; if the marker is
# already present, the per-extension loop skips the whole rebuild (see "Fast
# path"). Any edit to either script or a MODE change invalidates the marker and
# forces a one-time re-patch. Falls back to "always rebuild" if md5sum is
# unavailable. NOTE the namespace: "Claude RTL sig:" is deliberately distinct
# from the UI-extras marker so the two hooks, which patch the SAME index.js,
# never read each other's marker.
RTL_SIG=""
if command -v md5sum >/dev/null 2>&1; then
  _self_md5="$(md5sum "${BASH_SOURCE[0]}" 2>/dev/null | cut -c1-10)"
  _plan_md5="$(md5sum "$SCRIPT_DIR/patch-plan-rtl.js" 2>/dev/null | cut -c1-6)"
  _conf_md5="$(printf '%s' "$MODE" | md5sum 2>/dev/null | cut -c1-6)"
  RTL_SIG="$_self_md5-$_plan_md5-$_conf_md5"
fi
RTL_MARKER="Claude RTL sig:$RTL_SIG"

# ── Cross-package patch lock ─────────────────────────────────────────────
# The UI pack and the Hebrew RTL pack are BOTH SessionStart hooks, they fire
# at the same instant, and they patch the SAME index.js / index.css. Each one
# strips only its own marker block and appends its own, so two concurrent runs
# are a textbook lost update: both read the file, both build their temp from
# that same snapshot, and whoever mv-s last silently drops the other pack.
# That is the long-standing "one pack loaded, the other did not, reload a few
# times until both stick" symptom. One lock shared by both scripts serialises
# them. mkdir is the primitive because it is atomic, and HOME is the one path
# both scripts agree on wherever each happens to be installed.
#
# Fails OPEN. If the lock cannot be taken inside the ceiling we patch anyway -
# a SessionStart hook must never hold up the session. Worst case is the old
# behaviour, never worse than it.
PATCH_LOCK="$HOME/.claude/.cc-webview-patch.lock"
LOCK_HELD=false
mkdir -p "$HOME/.claude" 2>/dev/null
_lock_try=0
while [ "$_lock_try" -lt 50 ]; do          # 50 x 0.2s = 10s ceiling
  if mkdir "$PATCH_LOCK" 2>/dev/null; then LOCK_HELD=true; break; fi
  # Break a lock orphaned by a killed run (older than 60s).
  _lock_age=$(( $(date +%s) - $(stat -c %Y "$PATCH_LOCK" 2>/dev/null || date +%s) ))
  if [ "$_lock_age" -gt 60 ]; then rm -rf "$PATCH_LOCK" 2>/dev/null; continue; fi
  sleep 0.2
  _lock_try=$((_lock_try+1))
done
[ "$LOCK_HELD" = true ] && trap 'rm -rf "$PATCH_LOCK" 2>/dev/null' EXIT

FOUND=false
# Scan every host that keeps its own copy of the extension:
#   .vscode           stable, local install
#   .vscode-insiders  Insiders build
#   .vscode-server    Remote SSH / Codespaces / Dev Containers
#   .cursor           Cursor
#   .antigravity      Antigravity
# Each root is optional - the [ -f "$css" ] guard below skips whatever is not
# there, so a single-host machine is unaffected. The fork roots are best
# effort: they are not tested here, they just stop a fork user from silently
# getting one pack and not the other.
for dir in "$HOME"/.vscode{,-insiders,-server}/extensions/anthropic.claude-code-*/webview \
           "$HOME"/{.cursor,.antigravity}/extensions/anthropic.claude-code-*/webview; do
  css="$dir/index.css"
  js="$dir/index.js"
  [ -f "$css" ] || continue
  FOUND=true
  CHANGED=false

  # ── Fast path ────────────────────────────────────────────────────────
  # If both files already carry the current signature marker, there is
  # nothing to do. Skip WITHOUT building the temp + strip/append passes
  # (several seconds of wall-clock per session on a minified bundle, far
  # worse cold after sleep). A blocking SessionStart hook is the #1 cause of
  # the extension's "Subprocess initialization did not complete within
  # 60000ms" timeout, so a near-instant no-op here matters: two greps replace
  # the whole rebuild. Only meaningful in 'full' mode (the marker is only
  # written when the patch is applied); 'word' mode falls through to the cheap
  # strip-and-compare below, which converges to a no-op write.
  if [ "$MODE" = "full" ] && [ -n "$RTL_SIG" ] \
       && grep -qF "$RTL_MARKER" "$css" 2>/dev/null \
       && { [ ! -f "$js" ] || grep -qF "$RTL_MARKER" "$js" 2>/dev/null; }; then
    echo "CLAUDE_RTL_OK (already current): $dir"
    continue
  fi

  # ── CSS ──────────────────────────────────────────────────────────────
  # Build the desired file in a SAME-DIR temp, then atomically swap it in
  # ONLY if it differs from what's already on disk. Two reasons:
  #   (a) no "unpatched window" — the old code did `strip in place` then
  #       `append`, leaving a brief moment where the file had no patch. If the
  #       webview read during that gap it loaded raw, unstyled (LTR) UI.
  #   (b) a no-op resume is now truly no-op — when the file is already current
  #       we DON'T rewrite it. So a Reload after sleep loads the already-patched
  #       file instead of racing this hook's rewrite.
  # In 'word' mode the patch is simply not appended → the temp is the stripped
  # file, which removes any prior patch.
  csstmp="$css.rtl.tmp.$$"
  sed '/\/\* Claude RTL Patch Start \*\//,/\/\* Claude RTL Patch End \*\//d' "$css" > "$csstmp"
  # Trim trailing blank lines so the rebuild is byte-deterministic. Without
  # this, the heredoc's leading blank line stacks one extra newline per run,
  # and the cmp-skip below would never converge (file grows 1 byte/run).
  sed -i -e :a -e '/^[[:space:]]*$/{$d;N;ba}' "$csstmp"

  if [ "$MODE" = "full" ]; then
    cat >> "$csstmp" << CSSPATCH

$CSS_PATCH_START
/* $RTL_MARKER */
#root p,#root h1,#root h2,#root h3,#root h4,#root h5,#root h6,
#root li,#root blockquote,#root td,#root th,#root dd,#root dt,
#content p,#content h1,#content h2,#content h3,#content h4,#content h5,#content h6,
#content li,#content blockquote,#content td,#content th,#content dd,#content dt{
  unicode-bidi:isolate;text-align:start;
}
/* isolate, NOT embed. An embedding does not close its bidi run, so the text
   AFTER an inline code span starts a level run whose sos is L. The first
   number that follows then resolves LTR (W7) and jumps to the wrong side,
   dragging the period/comma/colon between them with it:
   a code-span word, then a period, then 47, came out as: word, 47, period.
   (No backticks in this comment on purpose: the CSSPATCH heredoc is unquoted,
   so a backtick here would run as a command substitution.)
   isolate makes the span one neutral object, so the digits keep the
   paragraph's RTL context. Harness: 9/15 with embed, 15/15 with isolate. */
#root pre,#root code,#content pre,#content code{
  direction:ltr;text-align:left;unicode-bidi:isolate;
}
#root li[style*="direction: rtl"],#content li[style*="direction: rtl"]{
  list-style-position:inside;
}
[class*="todoItem_"]{
  unicode-bidi:isolate;text-align:start;
}
[class*="messageInput"],[class*="mentionMirror"]{
  unicode-bidi:plaintext;text-align:start;
}
[class*="userMessage"]{
  unicode-bidi:isolate !important;
}
[class*="userMessage"] *:not(pre):not(code){
  direction:inherit;
}
[class*="questionText_"],[class*="questionTextLarge_"],
[class*="optionLabel_"],[class*="optionDescription_"],
[class*="questionHeader_"],[class*="questionBlock_"]{
  unicode-bidi:plaintext;text-align:start;
}
/* The timeline row is a flex column with align-items:flex-start. A summary
   block has no width of its own, so it shrink-wraps to its text and sits at
   the left edge whatever its direction; a line long enough to wrap fills the
   row and only then aligns. Give it the row's width, like the plain-text
   block already has. */
[class*="narrationSummary_"]{
  width:100%;unicode-bidi:isolate;text-align:start;
}
$CSS_PATCH_END
CSSPATCH
  fi
  if cmp -s "$csstmp" "$css"; then
    rm -f "$csstmp"
  else
    mv -f "$csstmp" "$css"
    CHANGED=true
  fi

  # ── JS ───────────────────────────────────────────────────────────────
  if [ -f "$js" ]; then
    jstmp="$js.rtl.tmp.$$"
    sed '/\/\* Claude RTL JS Start \*\//,/\/\* Claude RTL JS End \*\//d' "$js" > "$jstmp"
    # Trim trailing blank lines (see CSS note above) for a deterministic rebuild.
    sed -i -e :a -e '/^[[:space:]]*$/{$d;N;ba}' "$jstmp"

    if [ "$MODE" = "full" ]; then
      cat >> "$jstmp" << 'JSPATCH'

/* Claude RTL JS Start */
/* __RTL_SIG__ */
;(function(){
  var HEB_RE=/[\u0590-\u05FF]/;
  var LTR_RE=/[A-Za-z]/;
  var SEL='p,h1,h2,h3,h4,h5,h6,li,blockquote,td,th,dd,dt,[class*="questionText_"],[class*="questionTextLarge_"],[class*="optionLabel_"],[class*="optionDescription_"]';
  var USER_SEL='[class*="userMessage"]';
  /* Summarized-thinking rows ("(summarized)" label + one short paragraph).
     The paragraph inside is a plain <p> and is covered by SEL; the container
     gets its own verdict so the label follows the text's side. */
  var NARR_SEL='[class*="narrationSummary_"]';
  var RLM='\u200F';

  /* Publish the running RTL version for other packs to display (the UI-extras
     version line reads this lazily on right-click). Cross-pack handshake via a
     window global only - each pack stays fully functional without the other. */
  try{window.__ccRtlVersion='__RTL_VERSION__';}catch(e){}


  /* --- v5 detection: ratio-based with a pro-Hebrew 30% bar ------------------
     first-strong no longer overrides the proportion. A block that merely STARTS
     with a Hebrew word/name but is otherwise overwhelmingly English (e.g.
     "אתי's Schooler enrollment: joined...") now stays LTR instead of flipping
     RTL on that one leading char. Hebrew still wins on a low 30% bar, so
     genuinely mixed-but-Hebrew-leaning text goes RTL. firstStrong is kept only
     to distinguish "no strong char at all" (neutral -> null) from real text. */
  function detectDir(text){
    if(!text)return null;
    var firstStrong=null, rtl=0, ltr=0;
    for(var i=0;i<text.length;i++){
      var c=text.charCodeAt(i);
      if(c>=0x0590&&c<=0x05FF){
        rtl++;
        if(firstStrong===null)firstStrong='rtl';
      } else if((c>=0x41&&c<=0x5A)||(c>=0x61&&c<=0x7A)){
        ltr++;
        if(firstStrong===null)firstStrong='ltr';
      }
    }
    if(firstStrong===null)return null;
    var total=rtl+ltr;
    if(total>0&&(rtl/total)>=0.3)return'rtl';
    return'ltr';
  }

  /* --- v4 RLM anchor injection --- */
  function injectRLM(el){
    var first=el.firstChild;
    if(first&&first.nodeType===3&&first.textContent.charAt(0)===RLM)return;
    el.insertBefore(document.createTextNode(RLM),first);
  }

  /* --- Flip horizontal arrows in RTL context (Unicode doesn't auto-mirror) --- */
  var ARROW_FLIP={'\u2192':'\u2190','\u27F6':'\u27F5','\u21D2':'\u21D0','\u21E8':'\u21E6','\u21A6':'\u21A4','\u21AA':'\u21A9'};
  function flipArrows(el){
    var walker=document.createTreeWalker(el,NodeFilter.SHOW_TEXT,{acceptNode:function(n){
      var p=n.parentElement;
      while(p&&p!==el){
        var tag=p.tagName;
        if(tag==='PRE'||tag==='CODE')return NodeFilter.FILTER_REJECT;
        p=p.parentElement;
      }
      return NodeFilter.FILTER_ACCEPT;
    }});
    var n;
    while(n=walker.nextNode()){
      var t=n.textContent,out='',changed=false;
      for(var i=0;i<t.length;i++){
        var ch=t.charAt(i),rep=ARROW_FLIP[ch];
        if(rep){out+=rep;changed=true;}else{out+=ch;}
      }
      if(changed)n.textContent=out;
    }
  }

  function getText(el){
    var text='';
    for(var i=0;i<el.childNodes.length;i++){
      var n=el.childNodes[i];
      if(n.nodeType===3){text+=n.textContent;}
      else if(n.nodeType===1){
        if(n.matches('pre,code'))continue;   /* skip code even when wrapped in strong/em/a */
        text+=getText(n);                     /* recurse so nested code is excluded too */
      }
    }
    return text;
  }

  /* --- Strip leaked direction-mark escape-text from rendered prose -----------
     A model sometimes types the ESCAPE-TEXT of an RLM/LRM (backslash, u, then
     the hex digits) straight into chat prose, usually at a Hebrew/Latin seam.
     The renderer does not interpret escapes, so six visible junk characters
     land in the text. This removes that escape-text from prose text nodes.
     Deliberately narrow:
     - Only the LITERAL escape-text is removed. Real (invisible) RLM/LRM chars
       are untouched - this very patch injects RLM anchors on purpose
       (injectRLM), and they are harmless in display anyway.
     - PRE/CODE subtrees are skipped (same walker filter as flipArrows), so
       genuine code that discusses these escapes renders exactly as written.
     - Idempotent: a node is rewritten only when a match was actually removed,
       so the rewrite-triggered mutation finds nothing on its second pass. */
  var ESC_TEST=/\\u200[EF]/i;
  var ESC_ALL=/\\u200[EF]/gi;
  function stripEscapes(el){
    if(!el||el.nodeType!==1)return;
    var walker=document.createTreeWalker(el,NodeFilter.SHOW_TEXT,{acceptNode:function(n){
      var p=n.parentElement;
      while(p&&p!==el){
        var tag=p.tagName;
        if(tag==='PRE'||tag==='CODE')return NodeFilter.FILTER_REJECT;
        p=p.parentElement;
      }
      return NodeFilter.FILTER_ACCEPT;
    }});
    var n,batch=[];
    while(n=walker.nextNode()){
      if(ESC_TEST.test(n.textContent))batch.push(n);
    }
    for(var i=0;i<batch.length;i++){
      batch[i].textContent=batch[i].textContent.replace(ESC_ALL,'');
    }
  }

  function setDir(el){
    if(!el.matches||!el.matches(SEL))return;
    /* Anything inside a list item is governed as a group by setListDir (a list
       goes fully RTL iff ANY item leans Hebrew). Skip per-element detection for
       the li AND for any block wrapper inside it - "loose" lists wrap each
       item's content in a <p>, and detecting that <p> on its own would force a
       Latin-leaning item LTR with !important, overriding the list's RTL decision
       and stranding the bullet on the left. Let the list (direction inherited +
       text-align:start from the CSS patch) govern the inner blocks. */
    if(el.tagName==='LI'||(el.closest&&el.closest('li')))return;
    var text=getText(el);
    var dir=detectDir(text);
    if(dir==='rtl'){
      el.style.setProperty('direction','rtl','important');
      el.style.setProperty('text-align','right','important');
      injectRLM(el);
      flipArrows(el);
    } else if(dir==='ltr'){
      el.style.setProperty('direction','ltr','important');
      el.style.setProperty('text-align','left','important');
    }
  }

  function setUserDir(el){
    if(!el.matches||!el.matches(USER_SEL))return;
    var dir=detectDir(el.textContent);
    if(dir==='rtl'){
      el.style.setProperty('direction','rtl','important');
      el.style.setProperty('text-align','right','important');
      flipArrows(el);
    } else if(dir==='ltr'){
      el.style.setProperty('direction','ltr','important');
      el.style.setProperty('text-align','left','important');
    }
  }

  /* --- Summarized-thinking container: judged by its prose, label excluded ---
     The "(summarized)" label is Latin and would only dilute the ratio. */
  function setNarrDir(el){
    if(!el.matches||!el.matches(NARR_SEL))return;
    var text='';
    for(var i=0;i<el.children.length;i++){
      var ch=el.children[i];
      if(ch.className&&String(ch.className).indexOf('label_')===0)continue;
      text+=getText(ch)+' ';
    }
    var dir=detectDir(text);
    if(dir==='rtl'){
      el.style.setProperty('direction','rtl','important');
      el.style.setProperty('text-align','right','important');
      flipArrows(el);
    } else if(dir==='ltr'){
      el.style.setProperty('direction','ltr','important');
      el.style.setProperty('text-align','left','important');
    }
  }

  /* --- Re-judge everything that governs the block around a text change ------
     Used for characterData edits AND for text nodes inserted after their
     element. The element's own insertion was judged while it was still empty
     (detectDir on '' returns null, so nothing was set), and a text node that
     lands one tick later is a childList mutation whose added node is the text
     itself, not an element. Reproduced in a harness on the summarized-thinking
     row and kept as hardening; that row's visible left alignment itself came
     from its shrink-wrapped width, handled in the CSS block. */
  function reapplyAround(parent){
    if(!parent||parent.nodeType!==1)return;
    if(!(parent.closest&&parent.closest('pre,code')))stripEscapes(parent);
    var p=parent.closest(SEL);
    if(p)setDir(p);
    var n=parent.closest(NARR_SEL);
    if(n)setNarrDir(n);
    var t=parent.closest('table');
    if(t)setTableDir(t);
    var ul=parent.closest('ul,ol');
    if(ul)setListDir(ul);
  }

  /* --- Safety net: after every burst of mutations, re-judge any prose block
     that still carries no inline direction. Debounced, and only undecided
     elements are touched, so the steady-state cost is one cheap query. */
  var sweepTimer=null;
  function scheduleSweep(container){
    if(sweepTimer)return;
    sweepTimer=setTimeout(function(){
      sweepTimer=null;
      var els=container.querySelectorAll(SEL+','+NARR_SEL);
      for(var i=0;i<els.length;i++){
        var el=els[i];
        if(el.style&&el.style.direction)continue;
        if(el.matches(NARR_SEL))setNarrDir(el);else setDir(el);
      }
    },250);
  }

  /* --- List direction: decided by the AGGREGATE text of all items -----------
     A whole ul/ol goes RTL iff the COMBINED text of its bullets leans Hebrew
     (detectDir on the concatenation, same as setTableDir). This replaces the
     old "ANY item leans Hebrew -> whole list RTL" rule, which over-triggered:
     an English-dominant list with a few Hebrew terms/names sprinkled in (or one
     bullet that merely starts with a Hebrew word) used to flip the entire list
     right, stranding genuinely-English bullets on the right. Now the list
     reflects its dominant language. Trade-off: a Hebrew list carrying long
     English paths/commands could dip under the 30% bar and stay LTR - acceptable
     for the common case (English answers with sprinkled Hebrew terms).
     getText() ignores inline code, so `code`-only bullets stay neutral. */
  function setListDir(el){
    if(!el||(el.tagName!=='UL'&&el.tagName!=='OL'))return;
    var items=el.querySelectorAll(':scope > li');
    var agg='';
    for(var i=0;i<items.length;i++){agg+=getText(items[i])+' ';}
    var rtl=detectDir(agg)==='rtl';
    if(rtl){
      el.style.setProperty('direction','rtl','important');
      el.style.setProperty('text-align','right','important');
      for(var j=0;j<items.length;j++){
        var li=items[j];
        li.style.setProperty('direction','rtl','important');
        li.style.setProperty('text-align','right','important');
        /* Tight list: text sits directly in the li, so anchor it with an RLM.
           Loose list: the content is in a block child (<p>) that inherits the
           li's rtl direction - injecting an RLM into the li would become a stray
           inline box that drops the marker onto its own line, so skip it there. */
        var host=li.firstElementChild;
        if(!(host&&(host.tagName==='P'||host.tagName==='DIV')))injectRLM(li);
        flipArrows(li);
      }
    } else {
      el.style.setProperty('direction','ltr','important');
      el.style.setProperty('text-align','left','important');
      for(var k=0;k<items.length;k++){
        items[k].style.setProperty('direction','ltr','important');
        items[k].style.setProperty('text-align','left','important');
      }
    }
  }

  /* --- Table direction: flip column order based on cell content --- */
  function setTableDir(el){
    if(!el||el.tagName!=='TABLE')return;
    var cells=el.querySelectorAll('th,td');
    var text='';
    for(var i=0;i<cells.length;i++){text+=cells[i].textContent+' ';}
    var dir=detectDir(text);
    if(dir==='rtl'){
      el.style.setProperty('direction','rtl','important');
      el.style.setProperty('margin-left','auto','important');
      el.style.setProperty('margin-right','0','important');
    } else if(dir==='ltr'){
      el.style.setProperty('direction','ltr','important');
      el.style.setProperty('margin-left','0','important');
      el.style.setProperty('margin-right','auto','important');
    }
  }

  function watchUserDir(el){
    setUserDir(el);
    new MutationObserver(function(){setUserDir(el);})
      .observe(el,{attributes:true,attributeFilter:['style','dir']});
  }

  function initContainer(container){
    if(!container)return;
    stripEscapes(container);
    container.querySelectorAll(SEL).forEach(setDir);
    container.querySelectorAll(NARR_SEL).forEach(setNarrDir);
    container.querySelectorAll(USER_SEL).forEach(watchUserDir);
    container.querySelectorAll('table').forEach(setTableDir);
    container.querySelectorAll('ul,ol').forEach(setListDir);
    new MutationObserver(function(muts){
      for(var i=0;i<muts.length;i++){
        var m=muts[i];
        if(m.type==='characterData'){
          reapplyAround(m.target.parentElement);
          continue;
        }
        for(var j=0;j<m.addedNodes.length;j++){
          var nd=m.addedNodes[j];
          /* A text node arriving into an existing element: re-judge the
             blocks around it (see reapplyAround). */
          if(nd.nodeType===3){reapplyAround(nd.parentElement);continue;}
          if(nd.nodeType!==1)continue;
          if(!(nd.closest&&nd.closest('pre,code')))stripEscapes(nd);
          if(nd.matches&&nd.matches(SEL))setDir(nd);
          if(nd.matches&&nd.matches(NARR_SEL))setNarrDir(nd);
          if(nd.matches&&nd.matches(USER_SEL))watchUserDir(nd);
          if(nd.tagName==='TABLE')setTableDir(nd);
          if(nd.tagName==='UL'||nd.tagName==='OL')setListDir(nd);
          if(nd.querySelectorAll){
            nd.querySelectorAll(SEL).forEach(setDir);
            nd.querySelectorAll(NARR_SEL).forEach(setNarrDir);
            nd.querySelectorAll(USER_SEL).forEach(watchUserDir);
            nd.querySelectorAll('table').forEach(setTableDir);
            nd.querySelectorAll('ul,ol').forEach(setListDir);
          }
          var cn=nd.closest&&nd.closest(NARR_SEL);
          if(cn)setNarrDir(cn);
          var ct=nd.closest&&nd.closest('table');
          if(ct)setTableDir(ct);
          var cl=nd.closest&&nd.closest('ul,ol');
          if(cl)setListDir(cl);
        }
      }
      scheduleSweep(container);
    }).observe(container,{childList:true,subtree:true,characterData:true});
  }
  initContainer(document.getElementById('root'));
  initContainer(document.getElementById('content'));

  /* Watch for #content to appear dynamically (Plan view) */
  if(!document.getElementById('content')){
    new MutationObserver(function(muts,obs){
      var c=document.getElementById('content');
      if(c){obs.disconnect();initContainer(c);}
    }).observe(document.body,{childList:true,subtree:true});
  }

  /* --- Sidebar session history: per-item RTL/LTR alignment --- */
  function processHistoryList(){
    var items=document.querySelectorAll('[class*="sessionItem_"]');
    items.forEach(function(item){
      var name=item.querySelector('[class*="sessionName_"]');
      if(!name)return;
      var dir=detectDir(name.textContent);
      if(dir==='rtl'){
        name.style.setProperty('direction','rtl','important');
        name.style.setProperty('text-align','right','important');
      } else {
        name.style.setProperty('direction','ltr','important');
        name.style.setProperty('text-align','left','important');
      }
    });
    var btn=document.querySelectorAll('[class*="sessionsButtonText_"]');
    btn.forEach(function(el){
      var dir=detectDir(el.textContent);
      if(dir==='rtl'){
        el.style.setProperty('direction','rtl','important');
        el.style.setProperty('text-align','right','important');
      } else {
        el.style.setProperty('direction','ltr','important');
        el.style.setProperty('text-align','left','important');
      }
    });
  }
  processHistoryList();

  /* --- Composer: per-line direction by ratio ---------------------------------
     The prompt box is two stacked layers: a transparent contenteditable that
     owns the caret, and an absolutely positioned mirror that draws the glyphs.
     Both sat on CSS unicode-bidi:plaintext, which gives every line the
     direction of its FIRST STRONG character - so a single Latin letter at the
     head of an otherwise Hebrew line threw that whole line to the left.

     detectDir (the 30% ratio) is the rule we want, but it cannot be expressed
     in CSS, and a line is not an element: contenteditable plaintext-only keeps
     the text in flat nodes separated by real newlines. Wrapping lines in <div>s
     would give us elements, but the app reads the box with textContent, and
     textContent DROPS the newlines between block children - that would strip
     every line break out of the message actually sent.

     So a line becomes an inline <span> forced to display:block (its own block
     box, therefore its own direction and text-align), and each separating
     newline stays a real character inside a display:none span: invisible to
     layout, untouched in textContent. Caret and glyphs then live in the same
     block, so the caret cannot drift away from the text.

     The mirror is React-owned and must never have its children replaced (that
     is the crash class this pack learned the hard way), so it is dimmed and a
     clone of it - carrying the mention chips and the argument hint with their
     classes - is restructured the same way and laid over it. */
  var INPUT_SEL='[class*="messageInput_"]';   /* trailing _ : never the Container */
  var MIRROR_SEL='[class*="mentionMirror_"]';
  var LINE_ATTR='data-rtl-line';
  var NL_ATTR='data-rtl-nl';
  var SHADOW_ATTR='data-rtl-shadow';
  var LINE_CSS='display:block;unicode-bidi:isolate;text-align:start;';
  var rebuilding=false, composing=false;

  /* Distribute a flat node list into one block span per line, keeping every
     newline as a real character inside a hidden span. */
  function buildLines(dst,nodes){
    var line=null,lineText='';
    function openLine(){
      line=document.createElement('span');
      line.setAttribute(LINE_ATTR,'1');
      line.style.cssText=LINE_CSS;
      lineText='';
      dst.appendChild(line);
    }
    function closeLine(last){
      var d=detectDir(lineText);
      if(d)line.style.direction=d;
      /* an empty line still needs a line box, exactly like the newline it replaces */
      if(!line.firstChild)line.appendChild(document.createElement('br'));
      if(last)return;
      var nl=document.createElement('span');
      nl.setAttribute(NL_ATTR,'1');
      nl.style.display='none';
      nl.appendChild(document.createTextNode('\n'));
      dst.appendChild(nl);
    }
    openLine();
    for(var i=0;i<nodes.length;i++){
      var n=nodes[i];
      if(n.nodeType===3){
        var parts=n.data.split('\n');
        for(var k=0;k<parts.length;k++){
          if(k){closeLine(false);openLine();}
          if(parts[k]){line.appendChild(document.createTextNode(parts[k]));lineText+=parts[k];}
        }
      } else {
        line.appendChild(n);
        lineText+=n.textContent;
      }
    }
    closeLine(true);
  }

  /* Strict alternation line,nl,line,nl,...,line matching exactly these lines. */
  function structureMatches(el,lines){
    var kids=el.childNodes;
    if(kids.length!==lines.length*2-1)return false;
    for(var i=0;i<kids.length;i++){
      var k=kids[i];
      if(k.nodeType!==1)return false;
      if(i%2===0){
        if(!k.hasAttribute(LINE_ATTR)||k.textContent!==lines[i/2])return false;
        /* A line must be exactly its text, or exactly the <br> that stands in
           for an empty one. Anything else - typically the <br> left behind
           when the user starts typing on a line that was empty - paints a
           phantom blank row, and textContent alone would not reveal it. */
        var kids2=k.childNodes;
        if(lines[i/2]===''){
          if(kids2.length!==1||kids2[0].nodeName!=='BR')return false;
        } else {
          for(var q=0;q<kids2.length;q++)if(kids2[q].nodeType!==3)return false;
        }
      } else if(!k.hasAttribute(NL_ATTR)||k.textContent!=='\n')return false;
    }
    return true;
  }

  /* Direction is re-judged on every keystroke (a line can cross the 30% bar
     mid-word); this touches style only, never the DOM shape or the caret. */
  function refreshLineDirs(el){
    var ls=el.querySelectorAll('['+LINE_ATTR+']');
    for(var i=0;i<ls.length;i++){
      var d=detectDir(ls[i].textContent)||'';
      if(ls[i].style.direction!==d)ls[i].style.direction=d;
    }
  }

  /* Selection as character offsets into textContent. Range.toString() walks the
     DOM, not the layout, so the hidden newline spans are counted exactly like
     the newlines they hold. */
  function selOffsets(el){
    var s=window.getSelection();
    if(!s||!s.rangeCount)return null;
    var r=s.getRangeAt(0);
    if(!el.contains(r.startContainer)||!el.contains(r.endContainer))return null;
    var a=document.createRange(),b=document.createRange();
    a.selectNodeContents(el);b.selectNodeContents(el);
    try{
      a.setEnd(r.startContainer,r.startOffset);
      b.setEnd(r.endContainer,r.endOffset);
    }catch(e){return null;}
    return {start:a.toString().length,end:b.toString().length};
  }

  /* Absolute offset -> (line, column) is unambiguous, unlike walking text
     nodes: an offset right after a newline belongs to the START of the next
     line, not to the end of the previous one. */
  function placeCaret(el,text,off){
    if(off==null)return;
    var before=text.slice(0,off);
    var li=(before.match(/\n/g)||[]).length;
    var col=off-(before.lastIndexOf('\n')+1);
    var span=el.querySelectorAll('['+LINE_ATTR+']')[li];
    if(!span)return;
    var r=document.createRange(),placed=false;
    var w=document.createTreeWalker(span,NodeFilter.SHOW_TEXT),n,seen=0;
    while((n=w.nextNode())){
      if(col<=seen+n.data.length){r.setStart(n,col-seen);placed=true;break;}
      seen+=n.data.length;
    }
    if(!placed)r.setStart(span,0);
    r.collapse(true);
    try{var s=window.getSelection();s.removeAllRanges();s.addRange(r);}catch(e){}
  }

  function structureInput(el){
    if(rebuilding||composing)return;
    var text=el.textContent;
    /* An empty box must stay literally empty - the placeholder is a
       :empty:before rule, and any child of ours would silence it. */
    if(text===''){
      if(el.firstChild){rebuilding=true;el.textContent='';rebuilding=false;}
      return;
    }
    var lines=text.split('\n');
    if(structureMatches(el,lines)){refreshLineDirs(el);return;}
    var so=selOffsets(el);
    rewrite(el,text);
    placeCaret(el,text,so?so.start:null);
    /* Restoring the old scrollTop can leave the caret off-screen (a backspace
       that merged two lines, say). Only while the box is actually focused. */
    if(document.activeElement===el)revealCaret(el);
    followScroll(el);
  }

  function rewrite(el,text){
    /* Replacing the children resets scrollTop to 0. In a box tall enough to
       overflow that threw the view back to the first line on every structural
       change - and the caret with it. */
    var st=el.scrollTop,sl=el.scrollLeft;
    rebuilding=true;
    el.textContent='';
    var frag=document.createDocumentFragment();
    buildLines(frag,[document.createTextNode(text)]);
    el.appendChild(frag);
    rebuilding=false;
    el.scrollTop=st;el.scrollLeft=sl;
  }

  /* The app keeps the mirror in step with the editable on its scroll event
     (t1.scrollTop=M1.scrollTop). Our layer is a third element nobody syncs,
     and it is rebuilt from scratch on every keystroke, so it has to be put
     back in step both on scroll and after each rebuild. */
  function shadowOf(el){
    var h=el.parentElement;
    return h?h.querySelector('['+SHADOW_ATTR+']'):null;
  }
  function followScroll(el){
    var sh=shadowOf(el);
    if(!sh)return;
    if(sh.scrollTop!==el.scrollTop)sh.scrollTop=el.scrollTop;
    if(sh.scrollLeft!==el.scrollLeft)sh.scrollLeft=el.scrollLeft;
  }

  /* We preventDefault the browser's own newline insertion, so its "keep the
     caret on screen" behaviour does not run either. */
  function revealCaret(el){
    var s=window.getSelection();
    if(!s||!s.rangeCount)return;
    var rg=s.getRangeAt(0);
    if(!el.contains(rg.startContainer))return;
    var r=rg.getBoundingClientRect();
    if(!r||(!r.top&&!r.bottom&&!r.height)){
      /* A collapsed range on a line that holds only a <br> - the line you land
         on right after Enter - reports an empty rect. Fall back to the line
         box itself, or the caret never gets scrolled into view. */
      var n=rg.startContainer,e=n.nodeType===1?n:n.parentElement;
      var lineEl=e&&e.closest?e.closest('['+LINE_ATTR+']'):null;
      if(!lineEl)return;
      r=lineEl.getBoundingClientRect();
    }
    var b=el.getBoundingClientRect(),cs=getComputedStyle(el);
    var top=b.top+(parseFloat(cs.paddingTop)||0);
    var bot=b.bottom-(parseFloat(cs.paddingBottom)||0);
    if(r.top<top)el.scrollTop-=(top-r.top);
    else if(r.bottom>bot)el.scrollTop+=(r.bottom-bot);
  }

  function syncShadow(mirror){
    var host=mirror.parentElement;
    if(!host)return;
    var shadow=host.querySelector('['+SHADOW_ATTR+']');
    if(!shadow){
      shadow=document.createElement('div');
      shadow.setAttribute(SHADOW_ATTR,'1');
      shadow.setAttribute('aria-hidden','true');
      shadow.className=mirror.className;      /* same geometry, padding, chips */
      host.appendChild(shadow);
    }
    /* Never replace React's children - only dim them, on a property React
       does not manage for this element. */
    if(mirror.style.color!=='transparent')mirror.style.color='transparent';
    var clone=mirror.cloneNode(true),nodes=[];
    while(clone.firstChild){nodes.push(clone.firstChild);clone.removeChild(clone.firstChild);}
    shadow.textContent='';
    if(nodes.length)buildLines(shadow,nodes);
    var inp=host.querySelector(INPUT_SEL);
    if(inp)followScroll(inp);
  }

  function initComposer(){
    var inp=document.querySelector(INPUT_SEL);
    if(inp&&!inp.__ccRtlComposer){
      inp.__ccRtlComposer=true;
      inp.addEventListener('compositionstart',function(){composing=true;});
      inp.addEventListener('compositionend',function(){composing=false;structureInput(inp);});
      /* Plain Enter is the app's own (it sends, or inserts the newline itself),
         but Shift+Enter falls through to the browser, which answers it by
         SPLITTING the block at the caret - and that clones the hidden newline
         span, so the text gains a line break the user never typed. Insert the
         newline as a plain character instead: no block split, a real input
         event for React, and native handling of a replaced selection. */
      inp.addEventListener('beforeinput',function(ev){
        if(ev.inputType!=='insertParagraph'&&ev.inputType!=='insertLineBreak')return;
        var so=selOffsets(inp);
        if(!so)return;                      /* no usable selection: leave it alone */
        ev.preventDefault();
        var text=inp.textContent;
        var next=text.slice(0,so.start)+'\n'+text.slice(so.end);
        rewrite(inp,next);
        placeCaret(inp,next,so.start+1);
        revealCaret(inp);
        followScroll(inp);
        /* React reads the box on input; it never sees our DOM work otherwise */
        inp.dispatchEvent(new InputEvent('input',{bubbles:true,inputType:'insertLineBreak'}));
      });
      inp.addEventListener('input',function(){structureInput(inp);followScroll(inp);});
      inp.addEventListener('scroll',function(){followScroll(inp);});
      /* Programmatic textContent writes (mention accept, slash command, clear
         on send) fire no input event - the observer is what catches those. */
      new MutationObserver(function(){structureInput(inp);})
        .observe(inp,{childList:true,characterData:true,subtree:true});
      structureInput(inp);
    }
    var mir=document.querySelector(MIRROR_SEL+':not(['+SHADOW_ATTR+'])');
    if(mir&&!mir.__ccRtlComposer){
      mir.__ccRtlComposer=true;
      /* the shadow is a SIBLING, so our writes never re-enter this observer */
      new MutationObserver(function(){syncShadow(mir);})
        .observe(mir,{childList:true,characterData:true,subtree:true});
      syncShadow(mir);
    }
  }
  initComposer();

  new MutationObserver(function(){processHistoryList();initComposer();})
    .observe(document.body,{childList:true,subtree:true});
})();

/* ── Update notification banner (in-webview, once per version) ──
   The SessionStart hook's stdout is NOT shown to the user in the VSCode
   extension — it only enters the model's context — so the old "echo the
   update note" approach was invisible to the user. That was the root of the
   long-standing "update message never appears" bug. This shows the note in
   OUR injected DOM instead: a dismissible top banner, gated by localStorage so
   it appears once per new version, with a MAJOR-filtered changelog.
   Coordination with the UI-extras banner: deterministic stacking - this banner
   always sits at top:0 and the UI-extras banner (v1.21.0+) anchors itself
   below it, so neither follows the other (the old mutual-follow could
   ping-pong while both were visible). */
;(function(){
  var VER='__RTL_VERSION__';
  var KEY='claude-rtl-seen-version';
  if(!VER||VER.charAt(0)==='_')return;                 /* placeholder not substituted */
  var LOG; try{ LOG=__RTL_CHANGELOG__; }catch(e){ LOG=null; }   /* last 3 MAJOR versions */
  if(!LOG||!LOG.length)LOG=[{v:VER,n:''}];
  /* Pop only when there is a NEW MAJOR entry since the user last dismissed.
     LOG[0].v is the latest MAJOR version; a MAJOR=0 bump (maintenance/cosmetic)
     leaves LOG[0] unchanged, so the banner stays silent on those releases. */
  var TOP=LOG[0].v;
  /* Gate on "seen >= TOP", not exact match - exact match re-pops when a
     transiently-deployed higher version was dismissed and TOP then went back
     down (the UI repo hit this live 2026-06-10, fixed there in v1.17.1). */
  function vge(a,b){a=String(a).split('.');b=String(b).split('.');for(var i=0;i<3;i++){var x=+a[i]||0,y=+b[i]||0;if(x!==y)return x>y;}return true;}
  function dismissed(){try{var s=localStorage.getItem(KEY);return !!(s&&vge(s,TOP));}catch(e){return false;}}
  if(dismissed())return;
  var ID='claude-rtl-update-banner';
  /* Persist the dismissal with retries: localStorage writes are flushed to
     disk asynchronously (Chromium batches ~5s), and VSCode recycles the
     webview several times while a fresh window settles - a write made just
     before a recycle is LOST and the banner re-pops on the next incarnation
     (observed live 2026-06-11). Re-writing the same value every 3s for ~45s
     makes one of the writes land after the churn. */
  function persistSeen(){
    try{localStorage.setItem(KEY,TOP);}catch(e){}
    var k=0,t=setInterval(function(){try{localStorage.setItem(KEY,TOP);}catch(e){}if(++k>=15)clearInterval(t);},3000);
  }
  function mount(){
    if(document.getElementById(ID)||!document.body)return;
    if(dismissed())return 'stop';   /* THE v1.9.0 LOOP BUG: the gate ran once at script start only, while the retry loop kept calling mount() for 10s - an X-click (remove + setItem) was undone by the next 200ms tick remounting the banner, for the rest of the 10s window. Re-checking inside mount() makes a dismissal final. */
    var bar=document.createElement('div');
    bar.id=ID;
    bar.dir='rtl';
    /* z-index 99998 = one below the UI banner (99999) so the UI one wins any overlap during transitions */
    bar.style.cssText='position:fixed;top:0;left:0;right:0;z-index:99998;direction:rtl;text-align:right;display:flex;align-items:flex-start;gap:8px;padding:8px 12px;background:var(--vscode-editorWidget-background,#252526);border-bottom:1px solid var(--vscode-editorWidget-border,#454545);color:var(--vscode-foreground,#ccc);font-size:12px;line-height:1.45;box-shadow:0 2px 6px rgba(0,0,0,0.35);';
    var icon=document.createElement('span');icon.textContent='💡';icon.style.cssText='flex-shrink:0;';
    var txt=document.createElement('div');txt.style.cssText='flex:1;min-width:0;';
    var t1=document.createElement('div');t1.textContent='חבילת עברית (RTL) עודכנה ל-'+VER;t1.style.cssText='font-weight:700;margin-bottom:3px;';
    txt.appendChild(t1);
    LOG.forEach(function(it){
      var li=document.createElement('div');
      li.textContent='• '+it.v+(it.n?' - '+it.n:'');
      li.style.cssText='opacity:0.85;font-size:11px;margin-top:1px;';
      txt.appendChild(li);
    });
    var x=document.createElement('button');x.textContent='✕';x.title='סגור';
    x.style.cssText='flex-shrink:0;background:none;border:none;color:inherit;cursor:pointer;opacity:0.6;font-size:13px;padding:2px 6px;line-height:1;';
    x.addEventListener('mouseenter',function(){x.style.opacity='1';});
    x.addEventListener('mouseleave',function(){x.style.opacity='0.6';});
    x.addEventListener('click',function(){persistSeen();bar.remove();});
    bar.appendChild(icon);bar.appendChild(txt);bar.appendChild(x);
    document.body.appendChild(bar);
    /* If this version is dismissed in another window/webview sharing the same
       storage, hide here too instead of waiting for a reload. */
    window.addEventListener('storage',function(ev){
      if(ev.key===KEY&&dismissed()&&bar.isConnected)bar.remove();
    });
  }
  /* Delay the first mount ~10s: while a fresh VSCode window settles, the
     extension disposes and recreates the webview several times; banners shown
     during that churn are the ones whose dismissal gets lost. Short-lived
     incarnations now never show the banner at all, and the surviving one
     re-reads the gate right before mounting. */
  setTimeout(function(){
    if(mount()==='stop')return;
    var n=0,iv=setInterval(function(){if(mount()==='stop'||++n>50||document.getElementById(ID))clearInterval(iv);},200);
  },10000);
})();
/* Claude RTL JS End */
JSPATCH

      # Substitute placeholders. CHANGELOG_JS apostrophes are already U+2019,
      # and the notes hold no  " \ | &  so they are safe as sed replacements.
      sed -i "s|__RTL_SIG__|$RTL_MARKER|g" "$jstmp"
      sed -i "s|__RTL_VERSION__|$VERSION|g" "$jstmp"
      sed -i "s|__RTL_CHANGELOG__|$CHANGELOG_JS|g" "$jstmp"
    fi
    if cmp -s "$jstmp" "$js"; then
      rm -f "$jstmp"
    else
      mv -f "$jstmp" "$js"
      CHANGED=true
    fi
  fi

  # --- Patch Plan Preview webview in extension.js ---
  extjs="$(dirname "$dir")/extension.js"
  if [ -f "$extjs" ] && [ "$MODE" = "full" ]; then
    if ! grep -qF "Claude RTL Plan Patch" "$extjs"; then
      node "$SCRIPT_DIR/patch-plan-rtl.js" "$extjs" && CHANGED=true
    fi
  fi

  if [ "$CHANGED" = true ]; then
    echo "CLAUDE_RTL_PATCHED ($MODE): $dir"
  else
    echo "CLAUDE_RTL_OK (already current): $dir"
  fi
done


# Patching is done - hand the lock straight to the sibling pack instead of
# holding it through the auto-update section further down.
if [ "$LOCK_HELD" = true ]; then rm -rf "$PATCH_LOCK" 2>/dev/null; trap - EXIT; LOCK_HELD=false; fi
if [ "$FOUND" = false ]; then
  exit 0
fi

# ── Register SessionStart hook in ~/.claude/settings.json ────────────────────
SETTINGS="$HOME/.claude/settings.json"
HOOK_CMD="bash $SCRIPT_DIR/fix-claude-rtl.sh"
SCRIPT_ID="fix-claude-rtl.sh"

SETTINGS_PATH="$SETTINGS" HOOK_CMD="$HOOK_CMD" SCRIPT_ID="$SCRIPT_ID" \
node -e "
var fs = require('fs');
var p = process.env.SETTINGS_PATH;
var cmd = process.env.HOOK_CMD;
var id = process.env.SCRIPT_ID;
var s = {};
// A read that fails for an instant used to fall through to s={} and then
// rewrite this file from scratch, taking every other hook, the model and the
// permission rules with it. Claude Code writes the same file (model,
// effortLevel, the settings-menu toggles) without an atomic swap, and the
// sibling pack writes it too, so a torn read is a real event, not a theory.
// On a failed read we skip registration for this session - it runs again on
// the next one anyway.
if (fs.existsSync(p)) {
  try { s = JSON.parse(fs.readFileSync(p,'utf8')); }
  catch(e) { console.log('settings.json could not be read just now - skipping hook registration rather than risk overwriting it'); process.exit(0); }
}
var before = JSON.stringify(s);
if (!s.hooks) s.hooks = {};
if (!s.hooks.SessionStart) s.hooks.SessionStart = [];
var already = s.hooks.SessionStart.some(function(h){
  return h.hooks && h.hooks.some(function(hh){ return hh.command && hh.command.indexOf(id) !== -1; });
});
if (!already) {
  s.hooks.SessionStart.push({ hooks: [{ type: 'command', command: cmd }] });
  // Only touch the file when something actually changed, and swap it in
  // atomically so nobody can ever read a half-written settings.json from us.
  // In steady state this writes nothing at all, which removes the race window
  // instead of merely surviving it.
  if (JSON.stringify(s) !== before) {
    var stmp = p + '.tmp' + process.pid;
    fs.writeFileSync(stmp, JSON.stringify(s, null, 2), 'utf8');
    fs.renameSync(stmp, p);
  }
  console.log('Hook registered:', cmd);
} else {
  console.log('Hook already registered');
}
" 2>/dev/null || echo "Note: could not register hook (node not found)"

# ── Auto-update (background, every session) ───────────────────────────────
# v1.9.0: the check no longer blocks session start and no longer waits 24h.
# Mirrors the UI-extras repo's mechanism (keep the two aligned).
#
# Part 1 — version check, spawned as a DETACHED background job: session start
# never waits on the network (the old synchronous check cost up to ~3s offline,
# inside a BLOCKING SessionStart hook). Gated to once per 5 minutes only so
# rapid-fire new chats don't hammer GitHub. Fetches BOTH fix-claude-rtl.sh and
# patch-plan-rtl.js from main; when the remote VERSION differs, the .sh passes
# bash -n and the .js is non-empty, the job swaps BOTH on disk (same-dir temp +
# atomic mv — never truncate a possibly-running script in place; .js FIRST, so
# a half-swap leaves old sh + new js and simply retries next time) and leaves a
# marker file. No exec — this session already ran the old patches.
#
# Part 2 — pending-update notice, on the FIRST session that runs the NEW
# script: the bundle on disk is freshly patched, but the webview in memory may
# still run the old injection until the window reloads. The hook's stdout is
# NOT rendered to the user — it lands in Claude's context — so the notice is
# written as an instruction TO CLAUDE to tell the user to reload. Printed once;
# after the reload the in-webview changelog banner takes over. (The in-webview
# banner itself needs no reload line: by the time it shows, the new code is
# already live.)
#
# Fails open on any error. auto_update=false in rtl-mode.conf disables the
# check (a marker left by an earlier download is still announced — it already
# happened).
SELF="$SCRIPT_DIR/$(basename "${BASH_SOURCE[0]}")"
NOTE_FILE="$SCRIPT_DIR/.rtl-update-pending"
if [ "$AUTO_UPDATE" = "true" ]; then
  STATE_FILE="$SCRIPT_DIR/.rtl-last-update-check"
  NOW=$(date +%s)
  LAST=0
  [ -f "$STATE_FILE" ] && LAST=$(cat "$STATE_FILE" 2>/dev/null || echo 0)
  if [ $((NOW - LAST)) -gt 300 ]; then
    echo "$NOW" > "$STATE_FILE"
    (
      TMP_SH="$(mktemp 2>/dev/null || echo "/tmp/rtl-sh-$$.sh")"
      TMP_JS="$(mktemp 2>/dev/null || echo "/tmp/rtl-js-$$.js")"
      if curl -fsSL --connect-timeout 5 --max-time 30 -o "$TMP_SH" "$REMOTE_BASE_URL/fix-claude-rtl.sh" 2>/dev/null \
         && curl -fsSL --connect-timeout 5 --max-time 30 -o "$TMP_JS" "$REMOTE_BASE_URL/patch-plan-rtl.js" 2>/dev/null; then
        # VERSION derives from the CHANGELOG_VERS array, so parse the first
        # quoted entry of that line rather than a literal VERSION= line.
        REMOTE_VER="$(grep -m1 '^CHANGELOG_VERS=' "$TMP_SH" | grep -oE '"[0-9][^"]*"' | head -1 | tr -d '"')"
        if [ -n "$REMOTE_VER" ] && [ "$REMOTE_VER" != "$VERSION" ] && bash -n "$TMP_SH" 2>/dev/null && [ -s "$TMP_JS" ]; then
          cp "$TMP_JS" "$SCRIPT_DIR/patch-plan-rtl.js.new.$$" \
            && mv -f "$SCRIPT_DIR/patch-plan-rtl.js.new.$$" "$SCRIPT_DIR/patch-plan-rtl.js" \
            && cp "$TMP_SH" "$SELF.new.$$" && mv -f "$SELF.new.$$" "$SELF" \
            && echo "$REMOTE_VER" > "$NOTE_FILE"
        fi
      fi
      rm -f "$TMP_SH" "$TMP_JS" "$SELF.new.$$" "$SCRIPT_DIR/patch-plan-rtl.js.new.$$"
    ) </dev/null >/dev/null 2>&1 &
  fi
fi
if [ -f "$NOTE_FILE" ]; then
  PENDING_VER="$(head -1 "$NOTE_FILE" 2>/dev/null | tr -d '[:space:]')"
  rm -f "$NOTE_FILE"
  # Announce only if this process is actually the downloaded version (the swap
  # happened and the new script is the one running now); a stale/mismatched
  # marker is silently dropped.
  if [ "$PENDING_VER" = "$VERSION" ]; then
    echo ""
    echo "💡 חבילת העברית (Hebrew RTL) עודכנה אוטומטית לגרסה $VERSION (נבדק מול הגרסה: $COMPATIBLE_EXT_VERSION)"
    echo "חדש: $UPDATE_NOTE"
    echo "IMPORTANT instruction to Claude: the Claude Code Hebrew RTL pack was just auto-updated on disk, but the current window still runs the previous version. At the START of your reply, tell the user (in the conversation's language) that a Hebrew RTL update to v$VERSION was installed, briefly what is new (translate the Hebrew note above if needed), and that to activate it they should reload the window: press Ctrl+Shift+P, then run the command: Developer: Reload Window."
  fi
fi
