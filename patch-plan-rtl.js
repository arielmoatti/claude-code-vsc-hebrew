// Patches the Plan Preview webview in Claude Code's extension.js with RTL support
// Called from fix-claude-rtl.sh
var fs = require('fs');
var extPath = process.argv[2];
if (!extPath) { console.log('Usage: node patch-plan-rtl.js <extension.js path>'); process.exit(1); }

var MARKER = 'Claude RTL Plan Patch';
var data = fs.readFileSync(extPath, 'utf8');

if (data.indexOf(MARKER) !== -1) {
  console.log('Plan template already patched');
  process.exit(0);
}

// Find the Plan template literal: var Bk=`<!DOCTYPE html>...`;var c26=Bk
var tmplStart = data.indexOf('var Bk=`<!DOCTYPE html>');
if (tmplStart === -1) { console.log('Plan template not found'); process.exit(0); }
var tmplEnd = data.indexOf('`;var c26=Bk', tmplStart);
if (tmplEnd === -1) { console.log('Plan template end not found'); process.exit(0); }

var before = data.substring(0, tmplStart);
var tmpl = data.substring(tmplStart, tmplEnd);
var after = data.substring(tmplEnd);

// 1. Inject RTL CSS before </style>
var rtlCSS = [
  '/* ' + MARKER + ' */',
  'p,h1,h2,h3,h4,h5,h6,li,blockquote,td,th,dd,dt{unicode-bidi:isolate;text-align:start;}',
  'pre,code{direction:ltr;text-align:left;unicode-bidi:embed;}'
].join('');

tmpl = tmpl.replace('</style>', rtlCSS + '</style>');

// 2. Inject RTL JS before vscode.postMessage({ type: 'ready' });
var rtlJS = [
  ';(function(){',
  'var H=/[\\u0590-\\u05FF]/,L=/[A-Za-z]/;',
  'var S="p,h1,h2,h3,h4,h5,h6,li,blockquote,td,th,dd,dt";',
  'var RLM="\\u200F";',
  'function detect(t){',
  '  if(!t)return null;var f=null,r=0,l=0;',
  '  for(var i=0;i<t.length;i++){var c=t.charCodeAt(i);',
  '    if(c>=1424&&c<=1535){r++;if(f===null)f="rtl"}',
  '    else if((c>=65&&c<=90)||(c>=97&&c<=122)){l++;if(f===null)f="ltr"}}',
  '  if(f===null)return null;if(f==="rtl")return"rtl";',
  '  var tot=r+l;if(tot>0&&r/tot>=0.3)return"rtl";return"ltr"}',
  'function fix(el){',
  '  var t="";for(var i=0;i<el.childNodes.length;i++){var n=el.childNodes[i];',
  '    if(n.nodeType===3)t+=n.textContent;',
  '    else if(n.nodeType===1&&!n.matches("pre,code"))t+=n.textContent}',
  '  var d=detect(t);',
  '  if(d==="rtl"){el.style.setProperty("direction","rtl","important");',
  '    el.style.setProperty("text-align","right","important");',
  '    var f=el.firstChild;',
  '    if(!f||f.nodeType!==3||f.textContent.charAt(0)!==RLM)',
  '      el.insertBefore(document.createTextNode(RLM),f)}',
  '  else if(d==="ltr"){el.style.setProperty("direction","ltr","important");',
  '    el.style.setProperty("text-align","left","important")}}',
  'function initC(c){if(!c)return;c.querySelectorAll(S).forEach(fix);',
  '  new MutationObserver(function(ms){',
  '    for(var i=0;i<ms.length;i++){var m=ms[i];',
  '      if(m.type==="characterData"){',
  '        var p=m.target.parentElement&&m.target.parentElement.closest(S);',
  '        if(p)fix(p);continue}',
  '      for(var j=0;j<m.addedNodes.length;j++){var nd=m.addedNodes[j];',
  '        if(nd.nodeType!==1)continue;',
  '        if(nd.matches&&nd.matches(S))fix(nd);',
  '        if(nd.querySelectorAll)nd.querySelectorAll(S).forEach(fix)}}',
  '  }).observe(c,{childList:true,subtree:true,characterData:true})}',
  'var el=document.getElementById("content");',
  'if(el)initC(el);',
  'else{new MutationObserver(function(ms,obs){',
  '  var c2=document.getElementById("content");',
  '  if(c2){obs.disconnect();initC(c2)}',
  '}).observe(document.body,{childList:true,subtree:true})}',
  '})();'
].join('');

var readyMsg = "vscode.postMessage({ type: 'ready' });";
tmpl = tmpl.replace(readyMsg, rtlJS + readyMsg);

fs.writeFileSync(extPath, before + tmpl + after, 'utf8');
console.log('Plan template patched');
