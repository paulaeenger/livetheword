import streamlit as st

st.set_page_config(page_title="LiveTheWord", page_icon="📖", layout="wide")
st.title("LiveTheWord")
st.caption("Deployed Streamlit app ✅")

st.sidebar.header("Options")
translation = st.sidebar.selectbox("Choose translation (demo)", ["KJV","NIV","ESV","NASB","NRSV"], index=0)
show_word_count = st.sidebar.checkbox("Show word count", value=True)

ref = st.text_input("Scripture reference", placeholder="e.g., John 3:16")
text = st.text_area("Paste the verse text", height=150)

col1, col2 = st.columns(2)
if col1.button("Summarize"):
    if not text.strip():
        st.warning("Please paste some verse text first.")
    else:
        key_point = text.strip().split(".")[0][:220]
        st.subheader("Key Point")
        st.write(f"({translation}) {key_point}…")
        if show_word_count:
            st.caption(f"Word count: {len(text.split())}")

if col2.button("Clear"):
    st.session_state.clear()
    st.rerun()
