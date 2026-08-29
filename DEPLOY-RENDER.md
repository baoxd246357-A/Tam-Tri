# Deploy AI Site Control v1.1 on Render

1. Create a GitHub repository and upload this project.
2. In Render: New -> Web Service -> connect the GitHub repository.
3. Render should detect the Python app. If it asks:
   - Build Command: `pip install -r requirements.txt`
   - Start Command: `uvicorn app.main:app --host 0.0.0.0 --port $PORT`
4. Add Environment Variables:
   - `OPENAI_API_KEY` = your OpenAI API key
   - `OPENAI_MODEL` = `gpt-5.6-luna`
5. Deploy.
6. Open the generated `https://....onrender.com` URL on the phone.
7. Test `/health` first, then create a Site Visit and capture a photo.

IMPORTANT:
- Render Free web services spin down after inactivity and local files are ephemeral.
- This prototype stores SQLite and uploaded images locally, so do not use it as the permanent project record yet.
- Next production step: move DB to PostgreSQL and photos to object storage.
