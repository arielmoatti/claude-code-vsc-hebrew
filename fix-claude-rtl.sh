#!/bin/bash
# ── Package version ───────────────────────────────────────────────────────
# Bump VERSION only on meaningful code changes (not README-only commits).
# UPDATE_NOTE + COMPATIBLE_EXT_VERSION are shown to users at session start
# when auto-update runs.
VERSION="1.0.3"
COMPATIBLE_EXT_VERSION="2.1.119"
UPDATE_NOTE="יישור משופר לרשימות מקוננות בתוך הודעות משתמש"
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

FOUND=false
for dir in "$HOME/.vscode/extensions"/anthropic.claude-code-*/webview; do
  css="$dir/index.css"
  js="$dir/index.js"
  [ -f "$css" ] || continue
  FOUND=true
  CHANGED=false

  HAS_CSS_PATCH=false
  if grep -qF "$CSS_PATCH_START" "$css"; then
    HAS_CSS_PATCH=true
  fi

  # Remove old patch (v3 or earlier v4) to re-apply cleanly
  if [ "$HAS_CSS_PATCH" = true ]; then
    sed -i '/\/\* Claude RTL Patch Start \*\//,/\/\* Claude RTL Patch End \*\//d' "$css"
    HAS_CSS_PATCH=false
    CHANGED=true
  fi

  if [ "$MODE" = "full" ] && [ "$HAS_CSS_PATCH" = false ]; then
    cat >> "$css" << CSSPATCH

$CSS_PATCH_START
#root p,#root h1,#root h2,#root h3,#root h4,#root h5,#root h6,
#root li,#root blockquote,#root td,#root th,#root dd,#root dt,
#content p,#content h1,#content h2,#content h3,#content h4,#content h5,#content h6,
#content li,#content blockquote,#content td,#content th,#content dd,#content dt{
  unicode-bidi:isolate;text-align:start;
}
#root pre,#root code,#content pre,#content code{
  direction:ltr;text-align:left;unicode-bidi:embed;
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
$CSS_PATCH_END
CSSPATCH
    CHANGED=true
  fi

  if [ -f "$js" ]; then
    HAS_JS_PATCH=false
    if grep -qF "$JS_PATCH_START" "$js"; then
      HAS_JS_PATCH=true
    fi

    # Remove old JS patch to re-apply cleanly
    if [ "$HAS_JS_PATCH" = true ]; then
      sed -i '/\/\* Claude RTL JS Start \*\//,/\/\* Claude RTL JS End \*\//d' "$js"
      HAS_JS_PATCH=false
      CHANGED=true
    fi

    if [ "$MODE" = "full" ] && [ "$HAS_JS_PATCH" = false ]; then
      cat >> "$js" << 'JSPATCH'

/* Claude RTL JS Start */
;(function(){
  var HEB_RE=/[\u0590-\u05FF]/;
  var LTR_RE=/[A-Za-z]/;
  var SEL='p,h1,h2,h3,h4,h5,h6,li,blockquote,td,th,dd,dt,[class*="questionText_"],[class*="questionTextLarge_"],[class*="optionLabel_"],[class*="optionDescription_"]';
  var USER_SEL='[class*="userMessage"]';
  var RLM='\u200F';

  /* --- v4 smart detection: first-strong + 30% threshold --- */
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
    if(firstStrong==='rtl')return'rtl';
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
      if(n.nodeType===3)text+=n.textContent;
      else if(n.nodeType===1&&!n.matches('pre,code'))text+=n.textContent;
    }
    return text;
  }

  function setDir(el){
    if(!el.matches||!el.matches(SEL))return;
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
    container.querySelectorAll(SEL).forEach(setDir);
    container.querySelectorAll(USER_SEL).forEach(watchUserDir);
    container.querySelectorAll('table').forEach(setTableDir);
    new MutationObserver(function(muts){
      for(var i=0;i<muts.length;i++){
        var m=muts[i];
        if(m.type==='characterData'){
          var parent=m.target.parentElement;
          if(parent){
            var p=parent.closest(SEL);
            if(p)setDir(p);
            var t=parent.closest('table');
            if(t)setTableDir(t);
          }
          continue;
        }
        for(var j=0;j<m.addedNodes.length;j++){
          var nd=m.addedNodes[j];
          if(nd.nodeType!==1)continue;
          if(nd.matches&&nd.matches(SEL))setDir(nd);
          if(nd.matches&&nd.matches(USER_SEL))watchUserDir(nd);
          if(nd.tagName==='TABLE')setTableDir(nd);
          if(nd.querySelectorAll){
            nd.querySelectorAll(SEL).forEach(setDir);
            nd.querySelectorAll(USER_SEL).forEach(watchUserDir);
            nd.querySelectorAll('table').forEach(setTableDir);
          }
          var ct=nd.closest&&nd.closest('table');
          if(ct)setTableDir(ct);
        }
      }
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
  new MutationObserver(function(){processHistoryList();})
    .observe(document.body,{childList:true,subtree:true});
})();
/* Claude RTL JS End */
JSPATCH
      CHANGED=true
    elif [ "$MODE" = "word" ] && [ "$HAS_JS_PATCH" = true ]; then
      sed -i '/\/\* Claude RTL JS Start \*\//,/\/\* Claude RTL JS End \*\//d' "$js"
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
  fi
done

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
if (fs.existsSync(p)) { try { s = JSON.parse(fs.readFileSync(p,'utf8')); } catch(e) {} }
if (!s.hooks) s.hooks = {};
if (!s.hooks.SessionStart) s.hooks.SessionStart = [];
var already = s.hooks.SessionStart.some(function(h){
  return h.hooks && h.hooks.some(function(hh){ return hh.command && hh.command.indexOf(id) !== -1; });
});
if (!already) {
  s.hooks.SessionStart.push({ hooks: [{ type: 'command', command: cmd }] });
  fs.writeFileSync(p, JSON.stringify(s, null, 2), 'utf8');
  console.log('Hook registered:', cmd);
} else {
  console.log('Hook already registered');
}
" 2>/dev/null || echo "Note: could not register hook (node not found)"

# ── Auto-update (once per 24h) ────────────────────────────────────────────
# Runs at the END of the script so the Hebrew notification is the LAST thing
# printed — Claude Code's SessionStart renderer only shows the last few lines,
# so placing the update message last guarantees users see it.
# Fetches BOTH fix-claude-rtl.sh and patch-plan-rtl.js from main, compares
# VERSION. If newer and .sh syntax-valid and .js non-empty → replaces both
# on disk for the next session. No exec — today's session already ran the
# old patches; new code takes effect on the next Reload Window anyway.
# Fails open on any error.
if [ "$AUTO_UPDATE" = "true" ]; then
  STATE_FILE="$SCRIPT_DIR/.rtl-last-update-check"
  NOW=$(date +%s)
  LAST=0
  [ -f "$STATE_FILE" ] && LAST=$(cat "$STATE_FILE" 2>/dev/null || echo 0)
  if [ $((NOW - LAST)) -gt 86400 ]; then
    echo "$NOW" > "$STATE_FILE"
    TMP_SH="$(mktemp 2>/dev/null || echo "/tmp/rtl-sh-$$.sh")"
    TMP_JS="$(mktemp 2>/dev/null || echo "/tmp/rtl-js-$$.js")"
    if curl -fsSL --connect-timeout 3 --max-time 8 -o "$TMP_SH" "$REMOTE_BASE_URL/fix-claude-rtl.sh" 2>/dev/null \
       && curl -fsSL --connect-timeout 3 --max-time 8 -o "$TMP_JS" "$REMOTE_BASE_URL/patch-plan-rtl.js" 2>/dev/null; then
      REMOTE_VER="$(grep -m1 '^VERSION=' "$TMP_SH" | sed 's/^VERSION="\(.*\)".*/\1/')"
      REMOTE_NOTE="$(grep -m1 '^UPDATE_NOTE=' "$TMP_SH" | sed 's/^UPDATE_NOTE="\(.*\)".*/\1/')"
      REMOTE_EXT_VER="$(grep -m1 '^COMPATIBLE_EXT_VERSION=' "$TMP_SH" | sed 's/^COMPATIBLE_EXT_VERSION="\(.*\)".*/\1/')"
      if [ -n "$REMOTE_VER" ] && [ "$REMOTE_VER" != "$VERSION" ] && bash -n "$TMP_SH" 2>/dev/null && [ -s "$TMP_JS" ]; then
        cp "$TMP_SH" "${BASH_SOURCE[0]}"
        cp "$TMP_JS" "$SCRIPT_DIR/patch-plan-rtl.js"
        echo "💡 חבילת עברית לקלוד קוד (נבדק מול הגרסה: $REMOTE_EXT_VER)"
        echo "תיקון חדש: $REMOTE_NOTE"
        echo "משהו לא עובד? פשוט לעשות Reload."
      fi
    fi
    rm -f "$TMP_SH" "$TMP_JS"
  fi
fi
