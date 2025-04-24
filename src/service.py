# service.py

from fastapi import FastAPI, HTTPException
from fastapi.responses import StreamingResponse
from pydantic import BaseModel
from io import BytesIO

from create_garantia import gerar_pdf_em_bytes

class GenerateRequest(BaseModel):
    pedido: str

app = FastAPI(
    title="GarantiA Service",
    version="0.1.0",
    description="Gera termo de garantia para semijoias"
)

@app.get("/")
def root():
    return {
        "service": "garantia-service",
        "operations": ["generate"]
    }

@app.post("/generate")
def generate(req: GenerateRequest):
    try:
        pdf_bytes = gerar_pdf_em_bytes(req.pedido)
        buf = BytesIO(pdf_bytes)
        buf.seek(0)
        return StreamingResponse(
            buf,
            media_type="application/pdf",
            headers={
                "Content-Disposition": f"attachment; filename=garantia_{req.pedido}.pdf"
            },
        )
    except Exception as e:
        raise HTTPException(status_code=400, detail=str(e))
