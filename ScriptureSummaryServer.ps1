param([int]$Port = 8080)

function Esc([string]$s){ [System.Net.WebUtility]::HtmlEncode($s) }
function UrlDecode([string]$s){ [System.Uri]::UnescapeDataString(($s -replace '\+',' ')) }
# ---------- PS 5.1-safe ----------
# ---------- CONFIG ----------
$val = [Environment]::GetEnvironmentVariable('OPENAI_API_KEY','User')
if ([string]::IsNullOrWhiteSpace($val)) { $val = $env:OPENAI_API_KEY }
$env:OPENAI_API_KEY = $val
$OpenAiKey = ($env:OPENAI_API_KEY).Trim()
if (-not $OpenAiKey) { Write-Error "Please set OPENAI_API_KEY (User scope)." ; exit 1 }

# Use GPT-4.1 mini with the correct dated identifier
$Model = "gpt-4.1-mini-2025-04-14"

# ---------- PROMPT ----------
$BasePrompt = @"
You are a respectful, non-preachy scripture study guide.
Task: Summarize a scripture chapter (or range) and provide life application for a general audience.

Return JSON in this exact shape:
{
  "reference": string,
  "overview": string,
  "historical_context": string,
  "summary": string,
  "key_verses": string[],
  "themes": string[],
  "life_application": string[],
  "reflection_questions": string[],
  "cross_references": string[]
}

Guidelines:
- Be accurate to the chapter's content. Avoid quoting long passages; paraphrase.
- Keep a warm, invitational tone.
- "Life application" should be practical and specific (habits, small steps, questions).
- If a theme is provided instead of a chapter, recommend 3-5 chapters and summarize the top one.
- If a range is provided (e.g., Mosiah 2-5), weave the arc concisely.
"@

# ---------- HTML UI ----------
function New-HomeHtml {
  param([string]$ErrorMessage = "", $Result = $null, [string]$SelectedLength = "standard")

  # === Full Standard Works ===
  $Canons = @(
    @{ key='bom';  name='Book of Mormon'; books=@(
      @{ name='1 Nephi'; chapters=22 }, @{ name='2 Nephi'; chapters=33 },
      @{ name='Jacob'; chapters=7 }, @{ name='Enos'; chapters=1 },
      @{ name='Jarom'; chapters=1 }, @{ name='Omni'; chapters=1 },
      @{ name='Words of Mormon'; chapters=1 }, @{ name='Mosiah'; chapters=29 },
      @{ name='Alma'; chapters=63 }, @{ name='Helaman'; chapters=16 },
      @{ name='3 Nephi'; chapters=30 }, @{ name='4 Nephi'; chapters=1 },
      @{ name='Mormon'; chapters=9 }, @{ name='Ether'; chapters=15 },
      @{ name='Moroni'; chapters=10 }
    )},
    @{ key='ot';   name='Bible - Old Testament'; books=@(
      @{ name='Genesis'; chapters=50 }, @{ name='Exodus'; chapters=40 },
      @{ name='Leviticus'; chapters=27 }, @{ name='Numbers'; chapters=36 },
      @{ name='Deuteronomy'; chapters=34 }, @{ name='Joshua'; chapters=24 },
      @{ name='Judges'; chapters=21 }, @{ name='Ruth'; chapters=4 },
      @{ name='1 Samuel'; chapters=31 }, @{ name='2 Samuel'; chapters=24 },
      @{ name='1 Kings'; chapters=22 }, @{ name='2 Kings'; chapters=25 },
      @{ name='1 Chronicles'; chapters=29 }, @{ name='2 Chronicles'; chapters=36 },
      @{ name='Ezra'; chapters=10 }, @{ name='Nehemiah'; chapters=13 },
      @{ name='Esther'; chapters=10 }, @{ name='Job'; chapters=42 },
      @{ name='Psalms'; chapters=150 }, @{ name='Proverbs'; chapters=31 },
      @{ name='Ecclesiastes'; chapters=12 }, @{ name='Song of Solomon'; chapters=8 },
      @{ name='Isaiah'; chapters=66 }, @{ name='Jeremiah'; chapters=52 },
      @{ name='Lamentations'; chapters=5 }, @{ name='Ezekiel'; chapters=48 },
      @{ name='Daniel'; chapters=12 }, @{ name='Hosea'; chapters=14 },
      @{ name='Joel'; chapters=3 }, @{ name='Amos'; chapters=9 },
      @{ name='Obadiah'; chapters=1 }, @{ name='Jonah'; chapters=4 },
      @{ name='Micah'; chapters=7 }, @{ name='Nahum'; chapters=3 },
      @{ name='Habakkuk'; chapters=3 }, @{ name='Zephaniah'; chapters=3 },
      @{ name='Haggai'; chapters=2 }, @{ name='Zechariah'; chapters=14 },
      @{ name='Malachi'; chapters=4 }
    )},
    @{ key='nt';   name='Bible - New Testament'; books=@(
      @{ name='Matthew'; chapters=28 }, @{ name='Mark'; chapters=16 },
      @{ name='Luke'; chapters=24 }, @{ name='John'; chapters=21 },
      @{ name='Acts'; chapters=28 }, @{ name='Romans'; chapters=16 },
      @{ name='1 Corinthians'; chapters=16 }, @{ name='2 Corinthians'; chapters=13 },
      @{ name='Galatians'; chapters=6 }, @{ name='Ephesians'; chapters=6 },
      @{ name='Philippians'; chapters=4 }, @{ name='Colossians'; chapters=4 },
      @{ name='1 Thessalonians'; chapters=5 }, @{ name='2 Thessalonians'; chapters=3 },
      @{ name='1 Timothy'; chapters=6 }, @{ name='2 Timothy'; chapters=4 },
      @{ name='Titus'; chapters=3 }, @{ name='Philemon'; chapters=1 },
      @{ name='Hebrews'; chapters=13 }, @{ name='James'; chapters=5 },
      @{ name='1 Peter'; chapters=5 }, @{ name='2 Peter'; chapters=3 },
      @{ name='1 John'; chapters=5 }, @{ name='2 John'; chapters=1 },
      @{ name='3 John'; chapters=1 }, @{ name='Jude'; chapters=1 },
      @{ name='Revelation'; chapters=22 }
    )},
    @{ key='dc';   name='Doctrine and Covenants'; books=@(
      @{ name='Doctrine and Covenants'; chapters=138 }
    )},
    @{ key='pgp';  name='Pearl of Great Price'; books=@(
      @{ name='Moses'; chapters=8 }, @{ name='Abraham'; chapters=5 },
      @{ name='Joseph Smith-Matthew'; chapters=1 },
      @{ name='Joseph Smith-History'; chapters=1 },
      @{ name='Articles of Faith'; chapters=1 }
    )}
  )

  # JSON for client (PS 5.1-safe)
  $canonsJson = ($Canons | ConvertTo-Json -Depth 10 -Compress)

  

  $resultHtml = ""
  $resultJsonTag = ""
  if ($Result) {
    $mkList = {
      param($title, $items)
      if ($items -and $items.Count -gt 0) {
        "<section class=""sec""><h3>$title</h3><ul>" +
          ($items | ForEach-Object { "<li>{0}</li>" -f (Esc([string]$_)) }) -join "" +
        "</ul></section>"
      } else { "" }
    }
    $resultJson = ($Result | ConvertTo-Json -Depth 10 -Compress)
    $resultJsonTag = "<script id=""result-json"" type=""application/json"">$(Esc($resultJson))</script>"

    $resultHtml = @"
<article class="card">
  <div class="card-head">
    <h2>$(Esc $Result.reference)</h2>
    <div class="actions">
      <button id="copyBtn" class="btn secondary">Copy</button>
      <button id="downloadBtn" class="btn secondary">Download .md</button>
    </div>
  </div>
  <section class="sec"><h3>Overview</h3><p>$(Esc $Result.overview)</p></section>
  <section class="sec"><h3>Historical Context</h3><p>$(Esc $Result.historical_context)</p></section>
  <section class="sec"><h3>Summary</h3><p>$(Esc $Result.summary)</p></section>
  $(& $mkList "Key Verses" $Result.key_verses)
  $(& $mkList "Themes" $Result.themes)
  $(& $mkList "Life Application" $Result.life_application)
  $(& $mkList "Reflection Questions" $Result.reflection_questions)
  $(& $mkList "Cross-References" $Result.cross_references)
</article>
"@
  }

@"
<!doctype html>
<html>
<head>
  <meta charset="utf-8" />
  <title>Scripture Summary</title>
  <meta name="viewport" content="width=device-width,initial-scale=1" />
  <style>
    :root { color-scheme: light; }
    * { box-sizing: border-box; }
    body { font-family: system-ui, -apple-system, Segoe UI, Roboto, sans-serif; margin:0; background:#fff; color:#111; }
    .wrap { max-width: 920px; margin: 0 auto; padding: 24px; }
    header { margin-bottom: 12px; }
    header h1 { font-size: 28px; margin: 0 0 6px; letter-spacing: -0.01em; }
    header p { color:#555; margin:0; }
    .card { border:1px solid #e5e5e5; border-radius:14px; padding:16px; margin-top: 12px; background:#fff; }
    .card-head { display:flex; align-items:center; justify-content:space-between; gap:12px; margin-bottom:4px; }
    .card-head h2 { font-size: 20px; margin: 0; }
    .actions { display:flex; gap:8px; flex-wrap:wrap; }
    .btn { background:#111; color:#fff; padding:8px 12px; border:0; border-radius:8px; cursor:pointer; font-size: 13px; }
    .btn.secondary { background:#f5f5f5; color:#111; border:1px solid #e5e5e5; }
    .btn:disabled { opacity:.6; cursor:default; }
    label { font-size:12px; color:#555; display:block; margin-bottom:6px; }
    input { 
      width:100%; 
      padding:10px; 
      border:1px solid #ccc; 
      border-radius:8px; 
      font-size:14px; 
      background:#fff !important; 
      color:#111 !important;
    }
    select {
      width:100%; 
      padding:10px; 
      border:1px solid #ccc; 
      border-radius:8px; 
      font-size:14px; 
      background-color: #fff !important;
      background-image: url("data:image/svg+xml,%3Csvg xmlns='http://www.w3.org/2000/svg' width='12' height='12' viewBox='0 0 12 12'%3E%3Cpath fill='%23333' d='M6 9L1 4h10z'/%3E%3C/svg%3E") !important;
      background-repeat: no-repeat !important;
      background-position: right 10px center !important;
      color:#111 !important;
      -webkit-appearance: none !important;
      -moz-appearance: none !important;
      appearance: none !important;
      padding-right: 30px;
      cursor: pointer;
      line-height: normal;
    }
    select::-ms-expand {
      display: none;
    }
    select option {
      background-color: #fff !important;
      background: #fff !important;
      color: #111 !important;
      padding: 8px;
    }
    .grid { display:grid; gap:12px; }
    .g3 { grid-template-columns: repeat(3, minmax(0, 1fr)); }
    @media (max-width: 720px) { .g3 { grid-template-columns: 1fr; } }
    .sec { margin-top: 10px; }
    .sec h3 { font-size: 15px; margin:10px 0 6px; color:#222; }
    .sec p, li { line-height:1.7; font-size:14px; }
    ul { margin:0; padding-left: 20px; }
    .error { background:#FEF2F2; border:1px solid #FEE2E2; color:#991B1B; padding:10px; border-radius:8px; margin-top:12px; }
    .footer { color:#777; font-size:12px; margin-top:14px; text-align:center; }
    .loader { display:none; align-items:center; gap:8px; color:#444; font-size:13px; }
    .loader.show { display:flex; }
    .spinner { width:14px; height:14px; border:2px solid #ddd; border-top-color:#111; border-radius:50%; animation: spin 0.9s linear infinite; }
    @keyframes spin { to { transform: rotate(360deg); } }
    
    /* Hide any script tags that might be visible */
    script { display: none !important; }
  </style>
</head>
<body>
  <div class="wrap">
    <header>
      <h1>Scripture Summary</h1>
      <p>Choose scripture set/book/chapter or search a theme or range; get clear summaries with real-life application.</p>
    </header>

    <form id="mainForm" method="post" action="/">
      <div class="card">
        <div class="grid g3">
          <div>
            <label>Scripture set</label>
            <select name="canon" id="canon"></select>
          </div>
          <div>
            <label>Book</label>
            <select name="book" id="book"></select>
          </div>
          <div>
            <label>Chapter</label>
            <select name="chapter" id="chapter"></select>
          </div>
        </div>

        <div class="grid g3" style="margin-top:12px">
          <div>
            <label>Or search (theme or range)</label>
            <input name="search" id="search" placeholder='e.g., "charity" or "Mosiah 2-5"'>
          </div>
          <div>
            <label>Focus (optional)</label>
            <input name="focus" placeholder="e.g., overcoming doubt, leadership, covenants">
          </div>
          <div>
            <label>Length</label>
            <select name="length">
              <option value="brief"$(if ($SelectedLength -eq 'brief') { ' selected' } else { '' })>Brief</option>
              <option value="standard"$(if ($SelectedLength -eq 'standard') { ' selected' } else { '' })>Standard</option>
              <option value="deep"$(if ($SelectedLength -eq 'deep') { ' selected' } else { '' })>Deep</option>
            </select>
          </div>
        </div>

        <div class="grid g3" style="margin-top:12px"><div><label style="visibility:hidden">_</label>
            <button id="submitBtn" type="submit" class="btn">Get Summary</button>
          </div>
          <div>
            <label style="visibility:hidden">_</label>
            <div class="loader" id="loader"><div class="spinner"></div>Summarizing...</div>
          </div>
        </div>
      </div>
    </form>

    $(if ($ErrorMessage) { "<div class=""error"">$(Esc($ErrorMessage))</div>" } else { "" })
    $resultHtml
    $resultJsonTag

    <div class="footer">Tip: Choose a Scripture set (e.g., Book of Mormon), then book + chapter - or paste ranges like "Mosiah 2-5".</div>
  </div>

  <script>
    try {
      // Embedded canons data directly in JavaScript
      const canons = [
        {
          key: 'bom',
          name: 'Book of Mormon',
          books: [
            {name: '1 Nephi', chapters: 22}, {name: '2 Nephi', chapters: 33},
            {name: 'Jacob', chapters: 7}, {name: 'Enos', chapters: 1},
            {name: 'Jarom', chapters: 1}, {name: 'Omni', chapters: 1},
            {name: 'Words of Mormon', chapters: 1}, {name: 'Mosiah', chapters: 29},
            {name: 'Alma', chapters: 63}, {name: 'Helaman', chapters: 16},
            {name: '3 Nephi', chapters: 30}, {name: '4 Nephi', chapters: 1},
            {name: 'Mormon', chapters: 9}, {name: 'Ether', chapters: 15},
            {name: 'Moroni', chapters: 10}
          ]
        },
        {
          key: 'ot',
          name: 'Bible - Old Testament',
          books: [
            {name: 'Genesis', chapters: 50}, {name: 'Exodus', chapters: 40},
            {name: 'Leviticus', chapters: 27}, {name: 'Numbers', chapters: 36},
            {name: 'Deuteronomy', chapters: 34}, {name: 'Joshua', chapters: 24},
            {name: 'Judges', chapters: 21}, {name: 'Ruth', chapters: 4},
            {name: '1 Samuel', chapters: 31}, {name: '2 Samuel', chapters: 24},
            {name: '1 Kings', chapters: 22}, {name: '2 Kings', chapters: 25},
            {name: '1 Chronicles', chapters: 29}, {name: '2 Chronicles', chapters: 36},
            {name: 'Ezra', chapters: 10}, {name: 'Nehemiah', chapters: 13},
            {name: 'Esther', chapters: 10}, {name: 'Job', chapters: 42},
            {name: 'Psalms', chapters: 150}, {name: 'Proverbs', chapters: 31},
            {name: 'Ecclesiastes', chapters: 12}, {name: 'Song of Solomon', chapters: 8},
            {name: 'Isaiah', chapters: 66}, {name: 'Jeremiah', chapters: 52},
            {name: 'Lamentations', chapters: 5}, {name: 'Ezekiel', chapters: 48},
            {name: 'Daniel', chapters: 12}, {name: 'Hosea', chapters: 14},
            {name: 'Joel', chapters: 3}, {name: 'Amos', chapters: 9},
            {name: 'Obadiah', chapters: 1}, {name: 'Jonah', chapters: 4},
            {name: 'Micah', chapters: 7}, {name: 'Nahum', chapters: 3},
            {name: 'Habakkuk', chapters: 3}, {name: 'Zephaniah', chapters: 3},
            {name: 'Haggai', chapters: 2}, {name: 'Zechariah', chapters: 14},
            {name: 'Malachi', chapters: 4}
          ]
        },
        {
          key: 'nt',
          name: 'Bible - New Testament',
          books: [
            {name: 'Matthew', chapters: 28}, {name: 'Mark', chapters: 16},
            {name: 'Luke', chapters: 24}, {name: 'John', chapters: 21},
            {name: 'Acts', chapters: 28}, {name: 'Romans', chapters: 16},
            {name: '1 Corinthians', chapters: 16}, {name: '2 Corinthians', chapters: 13},
            {name: 'Galatians', chapters: 6}, {name: 'Ephesians', chapters: 6},
            {name: 'Philippians', chapters: 4}, {name: 'Colossians', chapters: 4},
            {name: '1 Thessalonians', chapters: 5}, {name: '2 Thessalonians', chapters: 3},
            {name: '1 Timothy', chapters: 6}, {name: '2 Timothy', chapters: 4},
            {name: 'Titus', chapters: 3}, {name: 'Philemon', chapters: 1},
            {name: 'Hebrews', chapters: 13}, {name: 'James', chapters: 5},
            {name: '1 Peter', chapters: 5}, {name: '2 Peter', chapters: 3},
            {name: '1 John', chapters: 5}, {name: '2 John', chapters: 1},
            {name: '3 John', chapters: 1}, {name: 'Jude', chapters: 1},
            {name: 'Revelation', chapters: 22}
          ]
        },
        {
          key: 'dc',
          name: 'Doctrine and Covenants',
          books: [{name: 'Doctrine and Covenants', chapters: 138}]
        },
        {
          key: 'pgp',
          name: 'Pearl of Great Price',
          books: [
            {name: 'Moses', chapters: 8}, {name: 'Abraham', chapters: 5},
            {name: 'Joseph Smith-Matthew', chapters: 1},
            {name: 'Joseph Smith-History', chapters: 1},
            {name: 'Articles of Faith', chapters: 1}
          ]
        }
      ];
      
      const canonSel = document.getElementById('canon');
      const bookSel  = document.getElementById('book');
      const chapSel  = document.getElementById('chapter');
      const form     = document.getElementById('mainForm');
      const loader   = document.getElementById('loader');
      const submitBtn= document.getElementById('submitBtn');

      function fillCanon() {
        canonSel.innerHTML = '';
        if (!canons || canons.length === 0) {
          const opt = document.createElement('option');
          opt.textContent = 'Error: No data';
          canonSel.appendChild(opt);
          return;
        }
        for (const c of canons) {
          const opt = document.createElement('option');
          opt.value = c.key;
          opt.textContent = c.name;
          canonSel.appendChild(opt);
        }
      }
      
      function fillBooks() {
        const c = canons.find(x => x.key === canonSel.value);
        if (!c || !c.books) {
          bookSel.innerHTML = '<option>No books found</option>';
          return;
        }
        bookSel.innerHTML = '';
        for (const b of c.books) {
          const opt = document.createElement('option');
          opt.value = b.name;
          opt.textContent = b.name;
          bookSel.appendChild(opt);
        }
      }
      
      function fillChapters() {
        const c = canons.find(x => x.key === canonSel.value);
        if (!c || !c.books) {
          chapSel.innerHTML = '<option>No chapters found</option>';
          return;
        }
        const b = c.books.find(x => x.name === bookSel.value);
        if (!b) {
          chapSel.innerHTML = '<option>No chapters found</option>';
          return;
        }
        chapSel.innerHTML = '';
        const count = b.chapters || 1;
        for (let i = 1; i <= count; i++) {
          const opt = document.createElement('option');
          opt.value = String(i);
          opt.textContent = String(i);
          chapSel.appendChild(opt);
        }
      }
      
      canonSel.addEventListener('change', () => { fillBooks(); fillChapters(); });
      bookSel.addEventListener('change', fillChapters);

      // Initialize on page load
      fillCanon();
      if (canons.length) { 
        canonSel.selectedIndex = 0;
        fillBooks(); 
        fillChapters();
      }

      form.addEventListener('submit', () => {
        loader.classList.add('show');
        submitBtn.setAttribute('disabled', 'true');
      });

      // Copy/Download helpers
      function resultToMarkdown(obj) {
        if (!obj) return '';
        const S = (h, v) => v ? '\n\n## '+h+'\n'+v : '';
        const L = (h, arr) => (arr && arr.length) ? '\n\n## '+h+'\n' + arr.map(x => '- '+x).join('\n') : '';
        return '# '+(obj.reference || 'Summary')
          + S('Overview', obj.overview)
          + S('Historical Context', obj.historical_context)
          + S('Summary', obj.summary)
          + L('Key Verses', obj.key_verses)
          + L('Themes', obj.themes)
          + L('Life Application', obj.life_application)
          + L('Reflection Questions', obj.reflection_questions)
          + L('Cross-References', obj.cross_references)
          + '\n';
      }
      const resultTag = document.getElementById('result-json');
      let resultData = null;
      if (resultTag) {
        try {
          const jsonText = resultTag.textContent;
          resultData = JSON.parse(jsonText);
        } catch(e) {
          console.error('JSON parse error:', e);
          console.error('JSON text:', resultTag.textContent);
        }
      }
      document.getElementById('copyBtn')?.addEventListener('click', async () => {
        const md = resultToMarkdown(resultData);
        try { await navigator.clipboard.writeText(md); } catch {}
      });
      document.getElementById('downloadBtn')?.addEventListener('click', () => {
        const md = resultToMarkdown(resultData);
        const ref = (resultData?.reference || 'summary').replace(/[^\w\- ]+/g,'').replace(/\s+/g,'_');
        const a = document.createElement('a');
        a.href = URL.createObjectURL(new Blob([md], {type: 'text/markdown'}));
        a.download = ref+'.md';
        document.body.appendChild(a); a.click(); a.remove();
      });
    } catch(err) {
      alert('JavaScript Error: ' + err.message);
      console.error('Full error:', err);
    }
  </script>
</body>
</html>
"@
}

# ---------- OpenAI call ----------
function Invoke-OpenAI {
  param(
    [string]$Reference,
    [string]$Focus = "",
    [ValidateSet('brief','standard','deep')][string]$Length = 'standard',
    [ValidateSet('general','teens','families','teachers')][string]$Audience = 'general'
  )

  if ([string]::IsNullOrWhiteSpace($Reference)) {
    throw "No reference provided. Choose a book/chapter or type a search/range."
  }

  $lengthGuidance = switch ($Length) {
    'brief'    { "CRITICAL: Keep responses VERY concise. Overview and context: 1-2 sentences each. Summary: 2-3 sentences max. Lists: 2-3 items each." }
    'standard' { "Provide balanced detail. Overview and context: 2-3 sentences each. Summary: 3-5 sentences. Lists: 3-5 items each." }
    'deep'     { "CRITICAL: Provide COMPREHENSIVE analysis. Overview and context: 3-5 sentences each with rich detail. Summary: 6+ sentences with thorough exploration. Lists: 5-8 items each with depth." }
  }

  $prompt = $BasePrompt + "`n`n" + @"
Now respond for:
REFERENCE: $Reference
FOCUS: $Focus
LENGTH REQUIREMENT: $lengthGuidance
AUDIENCE: $Audience
"@

  $body = @{
    model       = $Model
    temperature = 0.2
    messages    = @(
      @{ role = "system"; content = "Return only a valid JSON object that matches the schema in the prior message. No prose outside JSON." },
      @{ role = "user";   content = $prompt }
    )
  } | ConvertTo-Json -Depth 10

  $headers = @{
    "Authorization" = "Bearer $OpenAiKey"
    "Content-Type"  = "application/json"
  }

  Write-Host "[DEBUG] Sending request to OpenAI..." -ForegroundColor Cyan
  Write-Host "[DEBUG] Model: $Model" -ForegroundColor Cyan
  Write-Host "[DEBUG] Body: $body" -ForegroundColor DarkGray

  try {
    # Force UTF-8 encoding for the request
    $bodyBytes = [System.Text.Encoding]::UTF8.GetBytes($body)
    $req = [System.Net.WebRequest]::Create("https://api.openai.com/v1/chat/completions")
    $req.Method = "POST"
    $req.ContentType = "application/json; charset=utf-8"
    $req.ContentLength = $bodyBytes.Length
    foreach ($key in $headers.Keys) {
      if ($key -ne "Content-Type") {
        $req.Headers.Add($key, $headers[$key])
      }
    }
    
    $reqStream = $req.GetRequestStream()
    $reqStream.Write($bodyBytes, 0, $bodyBytes.Length)
    $reqStream.Close()
    
    $response = $req.GetResponse()
    $responseStream = $response.GetResponseStream()
    $reader = New-Object System.IO.StreamReader($responseStream, [System.Text.Encoding]::UTF8)
    $responseText = $reader.ReadToEnd()
    $reader.Close()
    $response.Close()
    
    $resp = $responseText | ConvertFrom-Json
    $text = $resp.choices[0].message.content
    if (-not $text) { throw "Empty response content." }
    
    # Fix common UTF-8 encoding issues using character codes
    $text = $text -replace [char]0xE2+[char]0x80+[char]0x99, "'"  # Smart apostrophe
    $text = $text -replace [char]0xE2+[char]0x80+[char]0x9C, '"'  # Smart quote open
    $text = $text -replace [char]0xE2+[char]0x80+[char]0x9D, '"'  # Smart quote close
    $text = $text -replace [char]0xE2+[char]0x80+[char]0x93, '-'  # En dash
    $text = $text -replace [char]0xE2+[char]0x80+[char]0x94, '-'  # Em dash
    
    return $text | ConvertFrom-Json
  } catch {
    $statusCode = $_.Exception.Response.StatusCode.value__
    $statusDesc = $_.Exception.Response.StatusDescription
    Write-Host "[ERROR] HTTP Status: $statusCode - $statusDesc" -ForegroundColor Red
    Write-Host "[ERROR] Exception Message: $($_.Exception.Message)" -ForegroundColor Red
    
    $errorDetail = "HTTP $statusCode - $statusDesc"
    try {
      if ($_.Exception.Response) {
        $stream = $_.Exception.Response.GetResponseStream()
        $reader = New-Object System.IO.StreamReader($stream)
        $responseBody = $reader.ReadToEnd()
        $reader.Close()
        if ($responseBody) {
          Write-Host "[ERROR DETAIL] Response Body: $responseBody" -ForegroundColor Red
          $errorDetail = $responseBody
        }
      }
    } catch {
      Write-Host "[ERROR] Could not read error stream: $($_.Exception.Message)" -ForegroundColor Red
    }
    throw "OpenAI API Error: $errorDetail"
  }
}

# ---------- HTTP server ----------
$listener = [System.Net.HttpListener]::new()
$prefix = "http://+:$Port/"
$listener.Prefixes.Add($prefix)
$listener.Start()
Write-Host "Scripture Summary running at $prefix (Ctrl+C to stop)" -ForegroundColor Green
Write-Host "Debug mode enabled - watch this console for errors" -ForegroundColor Yellow
Write-Host ""

try {
  while ($true) {
    $ctx = $listener.GetContext()

    if ($ctx.Request.HttpMethod -eq "GET") {
      Write-Host "[$(Get-Date -Format 'HH:mm:ss')] GET request received" -ForegroundColor Cyan
      $html = New-HomeHtml
      Write-Host "[$(Get-Date -Format 'HH:mm:ss')] HTML generated, length: $($html.Length) chars" -ForegroundColor Cyan
      $bytes = [System.Text.Encoding]::UTF8.GetBytes($html)
      $ctx.Response.ContentType = "text/html; charset=utf-8"
      $ctx.Response.OutputStream.Write($bytes, 0, $bytes.Length)
      $ctx.Response.Close()
      Write-Host "[$(Get-Date -Format 'HH:mm:ss')] Response sent successfully" -ForegroundColor Green
      continue
    }

    if ($ctx.Request.HttpMethod -eq "POST") {
      try {
        Write-Host "[$(Get-Date -Format 'HH:mm:ss')] POST request received" -ForegroundColor Cyan
        $reader = New-Object System.IO.StreamReader($ctx.Request.InputStream, $ctx.Request.ContentEncoding)
        $formRaw = $reader.ReadToEnd()
        Write-Host "[$(Get-Date -Format 'HH:mm:ss')] Form data: $formRaw" -ForegroundColor Yellow
        
        $pairs = $formRaw -split '&' | ForEach-Object {
          if ($_ -notmatch '=') { return }
          $k,$v = $_ -split '=',2
          $k = UrlDecode $k
          $v = UrlDecode $v
          [pscustomobject]@{ Key=$k; Value=$v }
        }
        $form = @{}
        foreach ($p in $pairs) { $form[$p.Key] = $p.Value }

        
# Normalize inputs (PS 5.1-safe)
$book    = ([string]$form['book']).Trim()
$chapter = ([string]$form['chapter']).Trim()
$search  = ([string]$form['search']).Trim()
$focus   = ([string]$form['focus']).Trim()
$length  = ([string]$form['length']).Trim().ToLower()

# Derive reference
if ($search) {
  $reference = $search
} elseif ($book -and $chapter) {
  $reference = "$book $chapter"
} elseif ($book) {
  $reference = $book
} else {
  $reference = ''
}

# Coalesce/validate length
if (@('brief','standard','deep') -notcontains $length) { $length = 'standard' }
$book     = $form['book']
        $chapter  = $form['chapter']
        $search   = $form['search']
        $focus    = $form['focus']
        $length   = $form['length']

        $reference = if ([string]::IsNullOrWhiteSpace($search)) { "$book $chapter" } else { $search }
        
        Write-Host "[$(Get-Date -Format 'HH:mm:ss')] Calling OpenAI with:" -ForegroundColor Cyan
        Write-Host "  Reference: $reference" -ForegroundColor Yellow
        Write-Host "  Focus: $focus" -ForegroundColor Yellow
        Write-Host "  Length: $length" -ForegroundColor Yellow
        Write-Host "  Model: $Model" -ForegroundColor Yellow

        $data = Invoke-OpenAI -Reference $reference -Focus $focus -Length $length -Audience 'general'

        Write-Host "[$(Get-Date -Format 'HH:mm:ss')] OpenAI response received successfully" -ForegroundColor Green
        $html = New-HomeHtml -Result $data -SelectedLength $length
        $bytes = [System.Text.Encoding]::UTF8.GetBytes($html)
        $ctx.Response.ContentType = "text/html; charset=utf-8"
        $ctx.Response.OutputStream.Write($bytes, 0, $bytes.Length)
        $ctx.Response.Close()
      } catch {
        Write-Host "[$(Get-Date -Format 'HH:mm:ss')] ERROR: $($_.Exception.Message)" -ForegroundColor Red
        Write-Host "[$(Get-Date -Format 'HH:mm:ss')] Stack trace: $($_.ScriptStackTrace)" -ForegroundColor Red
        
        $html = New-HomeHtml -ErrorMessage $_.Exception.Message
        $bytes = [System.Text.Encoding]::UTF8.GetBytes($html)
        $ctx.Response.ContentType = "text/html; charset=utf-8"
        $ctx.Response.OutputStream.Write($bytes, 0, $bytes.Length)
        $ctx.Response.Close()
      }
      continue
    }

    $ctx.Response.StatusCode = 404
    $ctx.Response.Close()
  }
} finally {
  $listener.Stop()
}


