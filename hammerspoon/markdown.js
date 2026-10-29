// The light Markdown translate.py asks a reply or a summary for, as HTML for
// the popup. Read by translate.lua into the popup page, and by
// test/translate.bats. Everything is escaped before any tag is made, so the
// only tags are the ones made here: the page can post messages to Hammerspoon.
// A list item starts with a <span class="mark">, so the page's innerText is the
// plain-text copy (・ bullets) and the rich copy drops it for a real bullet.
function renderMarkdown(raw) {
  const escape = (s) => s.replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;')
    .replace(/"/g, '&quot;');
  const inline = (s) => escape(s)
    .replace(/`([^`]+)`/g, '<code>$1</code>')
    .replace(/\*\*(.+?)\*\*/g, '<strong>$1</strong>');
  const out = [];
  let list = null;
  let para = [];
  const endPara = () => { if (para.length) out.push('<p>' + para.join('<br>') + '</p>'); para = []; };
  const endList = () => { if (list) out.push('</' + list + '>'); list = null; };
  const lines = raw.split('\n');
  for (let i = 0; i < lines.length; i++) {
    const line = lines[i];
    if (/^```/.test(line)) {
      endPara(); endList();
      const code = [];
      while (++i < lines.length && !/^```/.test(lines[i])) code.push(lines[i]);
      out.push('<pre><code>' + escape(code.join('\n')) + '</code></pre>');
      continue;
    }
    const bullet = line.match(/^\s*(?:[-*]\s+|・\s*)(.*)$/);
    const numbered = line.match(/^\s*(\d+)[.)]\s+(.*)$/);
    if (bullet || numbered) {
      endPara();
      const kind = bullet ? 'ul' : 'ol';
      if (list !== kind) { endList(); out.push('<' + kind + '>'); list = kind; }
      const mark = bullet ? '・' : numbered[1] + '. ';
      out.push('<li><span class="mark">' + mark + '</span>' + inline(bullet ? bullet[1] : numbered[2]) + '</li>');
      continue;
    }
    endList();
    if (line.trim() === '') { endPara(); continue; }
    const heading = line.match(/^#{1,6}\s+(.*)$/);
    if (heading) { endPara(); out.push('<p><strong>' + inline(heading[1]) + '</strong></p>'); continue; }
    para.push(inline(line));
  }
  endPara(); endList();
  return out.join('');
}
