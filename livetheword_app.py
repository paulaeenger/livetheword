import os, json, textwrap
import streamlit as st

# =========================
# Config / Environment
# =========================
st.set_page_config(page_title="Scripture Summary", page_icon="📖", layout="wide")

OPENAI_API_KEY = os.getenv("OPENAI_API_KEY", "").strip()
MODEL = "gpt-4.1-mini-2025-04-14"

if not OPENAI_API_KEY:
    st.error("OPENAI_API_KEY is not set. In Streamlit Cloud, add it under Settings → Secrets. Locally, set env var before running.")
    st.stop()

# Defer import so app still loads if key missing
try:
    from openai import OpenAI
    client = OpenAI(api_key=OPENAI_API_KEY)
except Exception as e:
    st.error("OpenAI client not available. Add `openai` to requirements.txt and redeploy.")
    st.exception(e)
    st.stop()

# =========================
# Prompt template (matches your PS version)
# =========================
BASE_PROMPT = """
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
""".strip()

def length_guidance(length: str) -> str:
    if length == "brief":
        return ("CRITICAL: Keep responses VERY concise. "
                "Overview and context: 1-2 sentences each. "
                "Summary: 2-3 sentences max. Lists: 2-3 items each.")
    if length == "deep":
        return ("CRITICAL: Provide COMPREHENSIVE analysis. "
                "Overview and context: 3-5 sentences each with rich detail. "
                "Summary: 6+ sentences with thorough exploration. Lists: 5-8 items each with depth.")
    return ("Provide balanced detail. Overview and context: 2-3 sentences each. "
            "Summary: 3-5 sentences. Lists: 3-5 items each.")

# =========================
# Data (Canons/Books/Chapters)
# =========================
CANONS = [
    {
        "key": "bom", "name": "Book of Mormon", "books": [
            {"name":"1 Nephi","chapters":22},{"name":"2 Nephi","chapters":33},
            {"name":"Jacob","chapters":7},{"name":"Enos","chapters":1},
            {"name":"Jarom","chapters":1},{"name":"Omni","chapters":1},
            {"name":"Words of Mormon","chapters":1},{"name":"Mosiah","chapters":29},
            {"name":"Alma","chapters":63},{"name":"Helaman","chapters":16},
            {"name":"3 Nephi","chapters":30},{"name":"4 Nephi","chapters":1},
            {"name":"Mormon","chapters":9},{"name":"Ether","chapters":15},
            {"name":"Moroni","chapters":10}
        ]
    },
    {
        "key": "ot", "name": "Bible - Old Testament", "books": [
            {"name":"Genesis","chapters":50},{"name":"Exodus","chapters":40},
            {"name":"Leviticus","chapters":27},{"name":"Numbers","chapters":36},
            {"name":"Deuteronomy","chapters":34},{"name":"Joshua","chapters":24},
            {"name":"Judges","chapters":21},{"name":"Ruth","chapters":4},
            {"name":"1 Samuel","chapters":31},{"name":"2 Samuel","chapters":24},
            {"name":"1 Kings","chapters":22},{"name":"2 Kings","chapters":25},
            {"name":"1 Chronicles","chapters":29},{"name":"2 Chronicles","chapters":36},
            {"name":"Ezra","chapters":10},{"name":"Nehemiah","chapters":13},
            {"name":"Esther","chapters":10},{"name":"Job","chapters":42},
            {"name":"Psalms","chapters":150},{"name":"Proverbs","chapters":31},
            {"name":"Ecclesiastes","chapters":12},{"name":"Song of Solomon","chapters":8},
            {"name":"Isaiah","chapters":66},{"name":"Jeremiah","chapters":52},
            {"name":"Lamentations","chapters":5},{"name":"Ezekiel","chapters":48},
            {"name":"Daniel","chapters":12},{"name":"Hosea","chapters":14},{"name":"Joel","chapters":3},
            {"name":"Amos","chapters":9},{"name":"Obadiah","chapters":1},{"name":"Jonah","chapters":4},
            {"name":"Micah","chapters":7},{"name":"Nahum","chapters":3},{"name":"Habakkuk","chapters":3},
            {"name":"Zephaniah","chapters":3},{"name":"Haggai","chapters":2},{"name":"Zechariah","chapters":14},
            {"name":"Malachi","chapters":4}
        ]
    },
    {
        "key": "nt", "name": "Bible - New Testament", "books": [
            {"name":"Matthew","chapters":28},{"name":"Mark","chapters":16},
            {"name":"Luke","chapters":24},{"name":"John","chapters":21},
            {"name":"Acts","chapters":28},{"name":"Romans","chapters":16},
            {"name":"1 Corinthians","chapters":16},{"name":"2 Corinthians","chapters":13},
            {"name":"Galatians","chapters":6},{"name":"Ephesians","chapters":6},
            {"name":"Philippians","chapters":4},{"name":"Colossians","chapters":4},
            {"name":"1 Thessalonians","chapters":5},{"name":"2 Thessalonians","chapters":3},
            {"name":"1 Timothy","chapters":6},{"name":"2 Timothy","chapters":4},
            {"name":"Titus","chapters":3},{"name":"Philemon","chapters":1},
            {"name":"Hebrews","chapters":13},{"name":"James","chapters":5},
            {"name":"1 Peter","chapters":5},{"name":"2 Peter","chapters":3},
            {"name":"1 John","chapters":5},{"name":"2 John","chapters":1},{"name":"3 John","chapters":1},
            {"name":"Jude","chapters":1},{"name":"Revelation","chapters":22}
        ]
    },
    {
        "key":"dc","name":"Doctrine and Covenants","books":[{"name":"Doctrine and Covenants","chapters":138}]
    },
    {
        "key":"pgp","name":"Pearl of Great Price","books":[
            {"name":"Moses","chapters":8},{"name":"Abraham","chapters":5},
            {"name":"Joseph Smith-Matthew","chapters":1},{"name":"Joseph Smith-History","chapters":1},
            {"name":"Articles of Faith","chapters":1}
        ]
    }
]

def canon_by_key(k:str):
    for c in CANONS:
        if c["key"] == k: return c
    return CANONS[0]

# =========================
# UI: selectors (canon → book → chapter) + free search
# =========================
st.title("Scripture Summary")

with st.form("selectors"):
    c1,c2,c3 = st.columns([1,1,1])
    with c1:
        canon_key = st.selectbox(
            "Scripture set",
            options=[c["key"] for c in CANONS],
            format_func=lambda k: canon_by_key(k)["name"],
            index=2  # default NT
        )
    canon = canon_by_key(canon_key)
    book_names = [b["name"] for b in canon["books"]]
    with c2:
        book = st.selectbox("Book", options=book_names, index=book_names.index("John") if "John" in book_names else 0)
    chapters = next(b["chapters"] for b in canon["books"] if b["name"] == book)
    with c3:
        chapter = st.selectbox("Chapter", options=list(range(1, chapters+1)), index=min(2, chapters-1))

    d1,d2,d3 = st.columns([2,2,1])
    with d1:
        search = st.text_input('Or search (theme or range)', placeholder='e.g., "charity" or "Mosiah 2-5"')
    with d2:
        focus = st.text_input("Focus (optional)", placeholder="e.g., overcoming doubt, leadership, covenants")
    with d3:
        length = st.selectbox("Length", ["brief","standard","deep"], index=1)

    submitted = st.form_submit_button("Get Summary")

# =========================
# Call OpenAI
# =========================
def build_user_prompt(reference:str, focus:str, length:str) -> str:
    return (
        BASE_PROMPT
        + "\n\nNow respond for:\n"
        + f"REFERENCE: {reference}\n"
        + f"FOCUS: {focus}\n"
        + f"LENGTH REQUIREMENT: {length_guidance(length)}\n"
        + "AUDIENCE: general\n"
    )

def to_markdown(obj:dict) -> str:
    if not obj: return ""
    def sec(h, v): return f"\n\n## {h}\n{v}" if v else ""
    def lst(h, arr): return f"\n\n## {h}\n" + "\n".join(f"- {x}" for x in arr) if arr else ""
    return ("# " + (obj.get("reference") or "Summary")
            + sec("Overview", obj.get("overview"))
            + sec("Historical Context", obj.get("historical_context"))
            + sec("Summary", obj.get("summary"))
            + lst("Key Verses", obj.get("key_verses"))
            + lst("Themes", obj.get("themes"))
            + lst("Life Application", obj.get("life_application"))
            + lst("Reflection Questions", obj.get("reflection_questions"))
            + lst("Cross-References", obj.get("cross_references"))
            + "\n")

result = None
error_msg = None

if submitted:
    reference = search.strip() if search.strip() else f"{book} {chapter}"
    try:
        with st.spinner("Summarizing…"):
            resp = client.chat.completions.create(
                model=MODEL,
                temperature=0.2,
                messages=[
                    {"role":"system", "content":"Return only a valid JSON object that matches the schema in the prior message. No prose outside JSON."},
                    {"role":"user", "content": build_user_prompt(reference, focus.strip(), length)}
                ],
            )
        text = resp.choices[0].message.content
        # Basic sanitation similar to your PS script
        replacements = {
            "\u2019":"'","\u201C":'"',"\u201D":'"',"\u2013":"-","\u2014":"-"
        }
        for k,v in replacements.items():
            text = text.replace(k,v)

        result = json.loads(text)
    except Exception as e:
        error_msg = f"OpenAI error: {e}"

# =========================
# Render Result
# =========================
if error_msg:
    st.error(error_msg)

if result:
    st.success(f"Reference: {result.get('reference','(unknown)')}")
    with st.container(border=True):
        st.subheader("Overview")
        st.write(result.get("overview",""))

        st.subheader("Historical Context")
        st.write(result.get("historical_context",""))

        st.subheader("Summary")
        st.write(result.get("summary",""))

        def list_section(title, items):
            if items:
                st.markdown(f"### {title}")
                st.markdown("\n".join(f"- {st.session_state.get('bullet_prefix','')}{x}" for x in items))

        list_section("Key Verses", result.get("key_verses"))
        list_section("Themes", result.get("themes"))
        list_section("Life Application", result.get("life_application"))
        list_section("Reflection Questions", result.get("reflection_questions"))
        list_section("Cross-References", result.get("cross_references"))

    md = to_markdown(result)
    colA, colB = st.columns(2)
    with colA:
        st.download_button("Download .md", data=md.encode("utf-8"), file_name=f"{(result.get('reference') or 'summary').replace(' ','_')}.md", mime="text/markdown")
    with colB:
        st.code(md, language="markdown")

# Helpful footer
st.caption("Tip: Choose a Scripture set, then pick book + chapter — or enter a theme/range like “Mosiah 2-5”.")
