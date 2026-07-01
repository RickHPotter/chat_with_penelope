import time
import io
import os
import uvicorn
from fastapi import FastAPI, HTTPException
from fastapi.responses import Response
from pydantic import BaseModel
from typing import Optional
from neutts import NeuTTS
import soundfile as sf

app = FastAPI(title="NeuTTS Fast API")
tts = None  # Global model instance

# Predefined samples mapping audio filenames to their transcripts
DEFAULT_SAMPLES = {
    "juliette.wav": "Dans les zones rurales où de nombreuses communautés n'ont pas accès à l'électricité, l'énergie solaire peut faire une énorme différence."
}

class TTSRequest(BaseModel):
    input_text: str
    ref_audio: Optional[str] = None  # Now optional, defaults to 'juliette.wav'
    ref_transcript: Optional[str] = None
    output_path: Optional[str] = None

@app.on_event("startup")
def startup_event():
    global tts
    print("Starting up: Loading NeuTTS models into memory (CPU)...")
    init_start = time.time()
    tts = NeuTTS(
        backbone_repo="neuphonic/neutts-nano-french",
        backbone_device="cpu",
        codec_repo="neuphonic/neucodec",
        codec_device="cpu",
    )
    print(f"Models loaded in {time.time() - init_start:.2f} seconds! Ready for fast generation.")

@app.post("/synthesize")
def synthesize(req: TTSRequest):
    if tts is None:
        raise HTTPException(status_code=500, detail="Model is not loaded yet.")

    # Determine reference audio, defaulting to juliette.wav in current directory
    audio_path = req.ref_audio or "juliette.wav"

    # Determine the reference transcript
    transcript = req.ref_transcript
    if not transcript:
        audio_filename = os.path.basename(audio_path)
        if audio_filename in DEFAULT_SAMPLES:
            transcript = DEFAULT_SAMPLES[audio_filename]
        else:
            raise HTTPException(
                status_code=400, 
                detail=f"ref_transcript is required for unknown audio sample: '{audio_filename}'"
            )

    gen_start = time.time()

    # 1. Encode reference
    try:
        ref_codes = tts.encode_reference(audio_path)
    except Exception as e:
        raise HTTPException(status_code=400, detail=f"Failed to load reference audio: {e}")

    # 2. Synthesize
    wav_output = tts.infer(req.input_text, ref_codes, transcript)

    # 3. Return or save
    if req.output_path:
        sf.write(req.output_path, wav_output, 24000)
        return {
            "status": "success", 
            "message": f"Saved to {req.output_path}",
            "time_taken": round(time.time() - gen_start, 2)
        }
    else:
        # Return raw WAV file over HTTP if no path is given
        buffer = io.BytesIO()
        sf.write(buffer, wav_output, 24000, format='WAV')
        buffer.seek(0)
        return Response(content=buffer.read(), media_type="audio/wav")

if __name__ == "__main__":
    print("Starting server on http://127.0.0.1:8000")
    uvicorn.run(app, host="127.0.0.1", port=8000)
