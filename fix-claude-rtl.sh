#!/bin/bash
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONF_FILE="$SCRIPT_DIR/rtl-mode.conf"
CSS_PATCH_START="/* Claude RTL Patch Start */"
CSS_PATCH_END="/* Claude RTL Patch End */"
JS_PATCH_START="/* Claude RTL JS Start */"
JS_PATCH_END="/* Claude RTL JS End */"

MODE=""
if [ -n "$1" ]; then
  MODE="$1"
  echo "$MODE" > "$CONF_FILE"
elif [ -f "$CONF_FILE" ]; then
  MODE="$(head -1 "$CONF_FILE" | tr -d '[:space:]')"
fi
if [ "$MODE" != "word" ] && [ "$MODE" != "full" ]; then
  MODE="full"
fi

FOUND=false
for dir in "$HOME/.vscode/extensions"/anthropic.claude-code-*/webview; do
  css="$dir/index.css"
  js="$dir/index.js"
  [ -f "$css" ] || continue
  FOUND=true
  CHANGED=false

  if grep -q "bidi-override" "$css"; then
    sed -i 's/unicode-bidi:[[:space:]]*bidi-override/unicode-bidi: normal/g' "$css"
    CHANGED=true
  fi

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
    } else if(dir==='ltr'){
      el.style.setProperty('direction','ltr','important');
      el.style.setProperty('text-align','left','important');
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
    new MutationObserver(function(muts){
      for(var i=0;i<muts.length;i++){
        var m=muts[i];
        if(m.type==='characterData'){
          var p=m.target.parentElement&&m.target.parentElement.closest(SEL);
          if(p)setDir(p);
          continue;
        }
        for(var j=0;j<m.addedNodes.length;j++){
          var nd=m.addedNodes[j];
          if(nd.nodeType!==1)continue;
          if(nd.matches&&nd.matches(SEL))setDir(nd);
          if(nd.matches&&nd.matches(USER_SEL))watchUserDir(nd);
          if(nd.querySelectorAll){
            nd.querySelectorAll(SEL).forEach(setDir);
            nd.querySelectorAll(USER_SEL).forEach(watchUserDir);
          }
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
