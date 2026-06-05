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
COMPATIBLE_EXT_VERSION="2.1.165"
CHANGELOG_VERS=(  "1.5.0" "1.4.0" "1.3.0" "1.2.0" "1.1.0" )
CHANGELOG_MAJOR=( "1"     "1"     "1"     "1"     "1"     )
CHANGELOG_NOTES=(
  "תיקון המשך ליישור רשימות: פריט באנגלית בתוך רשימה עברית נשאר מיושר לשמאל גם אחרי v1.4.0 כשתוכן הפריט עטוף בפסקה (רשימות עם רווח בין הפריטים). עכשיו כל הרשימה מתיישרת לימין באופן עקבי."
  "ברשימה עברית, פריט שמתחיל באנגלית (פקודה, שם שדה, נתיב) מתיישר עכשיו לימין עם שאר הרשימה במקום לבלוט שמאלה. רשימה שכולה אנגלית נשארת מיושרת לשמאל."
  "הודעות עדכון מופיעות כבאנר בתוך הצ’אט במקום בפלט נסתר."
  "אתחול הצ’אט כבר לא נתקע: ה-hook כמעט מיידי, במקום תקיעה של עד 60 שניות אחרי שינה."
  "ההזרקה נטענת מיד ואמינה אחרי שינה/פתיחה מחדש, בלי לדרוש כמה reload-ים."
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

FOUND=false
for dir in "$HOME/.vscode/extensions"/anthropic.claude-code-*/webview; do
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

  /* --- List direction: a whole ul/ol goes RTL iff ANY item leans Hebrew ------
     Per Ariel's rule: if even one bullet leans Hebrew (starts Hebrew, or is
     Hebrew-majority via detectDir), the ENTIRE list reads RTL so a lone Latin
     bullet doesn't stick out left. If NO item leans Hebrew (an all-English /
     all-code list), leave it LTR - forcing those right just hurts readability.
     getText() ignores inline code, so a bullet that is only `code` counts as
     neutral (won't trigger on its own, but inherits the list's RTL when a
     sibling is Hebrew). */
  function setListDir(el){
    if(!el||(el.tagName!=='UL'&&el.tagName!=='OL'))return;
    var items=el.querySelectorAll(':scope > li');
    var rtl=false;
    for(var i=0;i<items.length;i++){
      if(detectDir(getText(items[i]))==='rtl'){rtl=true;break;}
    }
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
    container.querySelectorAll(SEL).forEach(setDir);
    container.querySelectorAll(USER_SEL).forEach(watchUserDir);
    container.querySelectorAll('table').forEach(setTableDir);
    container.querySelectorAll('ul,ol').forEach(setListDir);
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
            var ul=parent.closest('ul,ol');
            if(ul)setListDir(ul);
          }
          continue;
        }
        for(var j=0;j<m.addedNodes.length;j++){
          var nd=m.addedNodes[j];
          if(nd.nodeType!==1)continue;
          if(nd.matches&&nd.matches(SEL))setDir(nd);
          if(nd.matches&&nd.matches(USER_SEL))watchUserDir(nd);
          if(nd.tagName==='TABLE')setTableDir(nd);
          if(nd.tagName==='UL'||nd.tagName==='OL')setListDir(nd);
          if(nd.querySelectorAll){
            nd.querySelectorAll(SEL).forEach(setDir);
            nd.querySelectorAll(USER_SEL).forEach(watchUserDir);
            nd.querySelectorAll('table').forEach(setTableDir);
            nd.querySelectorAll('ul,ol').forEach(setListDir);
          }
          var ct=nd.closest&&nd.closest('table');
          if(ct)setTableDir(ct);
          var cl=nd.closest&&nd.closest('ul,ol');
          if(cl)setListDir(cl);
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

/* ── Update notification banner (in-webview, once per version) ──
   The SessionStart hook's stdout is NOT shown to the user in the VSCode
   extension — it only enters the model's context — so the old "echo the
   update note" approach was invisible to the user. That was the root of the
   long-standing "update message never appears" bug. This shows the note in
   OUR injected DOM instead: a dismissible top banner, gated by localStorage so
   it appears once per new version, with a MAJOR-filtered changelog.
   Coordination with the UI-extras banner: both are position:fixed at the top,
   so this one measures the UI banner (if present) and offsets itself below it. */
;(function(){
  var VER='__RTL_VERSION__';
  var KEY='claude-rtl-seen-version';
  if(!VER||VER.charAt(0)==='_')return;                 /* placeholder not substituted */
  try{ if(localStorage.getItem(KEY)===VER)return; }catch(e){}
  var LOG; try{ LOG=__RTL_CHANGELOG__; }catch(e){ LOG=null; }   /* last 3 MAJOR versions */
  if(!LOG||!LOG.length)LOG=[{v:VER,n:''}];
  var ID='claude-rtl-update-banner';
  var UI_ID='claude-ui-update-banner';
  /* Sit below the UI-extras banner if it exists & is visible, else at top:0. */
  function place(bar){
    var ui=document.getElementById(UI_ID);
    var off=(ui&&ui.offsetParent!==null)?ui.getBoundingClientRect().bottom:0;
    bar.style.top=off+'px';
  }
  function mount(){
    if(document.getElementById(ID)||!document.body)return;
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
    x.addEventListener('click',function(){try{localStorage.setItem(KEY,VER);}catch(e){}bar.remove();});
    bar.appendChild(icon);bar.appendChild(txt);bar.appendChild(x);
    document.body.appendChild(bar);
    place(bar);
  }
  mount();
  /* Retry mount until DOM is ready, and keep re-placing for ~10s so we follow
     the UI banner appearing late or being dismissed. */
  var n=0,iv=setInterval(function(){
    mount();
    var bar=document.getElementById(ID);
    if(bar)place(bar);
    if(++n>50)clearInterval(iv);
  },200);
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
# Runs at the END of the script. The real user-facing notification is the
# in-webview banner above (the SessionStart hook's stdout is invisible to the
# user); the Hebrew echo here is kept only as a harmless log/trace line.
# Fetches BOTH fix-claude-rtl.sh and patch-plan-rtl.js from main, compares the
# newest CHANGELOG_VERS entry. If newer and .sh syntax-valid and .js non-empty
# → replaces BOTH on disk atomically for the next session. No exec — today's
# session already ran the old patches; new code takes effect on the next Reload
# Window anyway. Fails open on any error.
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
      # VERSION now derives from the CHANGELOG_VERS array, so parse the first
      # quoted entry of that line rather than a literal VERSION= line.
      REMOTE_VER="$(grep -m1 '^CHANGELOG_VERS=' "$TMP_SH" | grep -oE '"[0-9][^"]*"' | head -1 | tr -d '"')"
      REMOTE_NOTE="$(grep -A1 '^CHANGELOG_NOTES=' "$TMP_SH" | tail -1 | sed 's/^[[:space:]]*"//; s/"[[:space:]]*$//')"
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
