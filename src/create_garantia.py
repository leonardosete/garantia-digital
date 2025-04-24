# create_garantia.py

import re
import csv
import requests
from io import BytesIO
from pathlib import Path
from reportlab.lib.pagesizes import letter
from reportlab.lib.styles import getSampleStyleSheet, ParagraphStyle
from reportlab.lib.enums import TA_CENTER, TA_LEFT
from reportlab.platypus import (
    SimpleDocTemplate,
    Paragraph,
    Spacer,
    Frame,
    PageTemplate,
)

TEMPLATE_TXT = "template-garantia.txt"
IMG_FUNDO   = "logo-background.png"

def substituir_texto(template: str, dados: dict) -> str:
    for chave, valor in dados.items():
        placeholder = f"{{{{{chave}}}}}"
        if isinstance(valor, list):
            valor = "\n".join(str(item) for item in valor)
        template = template.replace(placeholder, valor)
    return template

def limpar_texto(texto: str) -> str:
    return re.sub(r"[^\x20-\x7E\u00A0-\u024F]", "", texto).strip()

def gerar_pdf_em_bytes(pedido: str) -> bytes:
    # 1) Baixa e filtra CSV
    url = (
        "https://docs.google.com/spreadsheets/d/"
        "1Sdp3IUc-pOoFhuHgWhNnqqwFoaJbHxreYQHg_ySt6FQ/export?format=csv"
    )
    resp = requests.get(url)
    resp.raise_for_status()
    reader = csv.reader(resp.text.splitlines(), delimiter=",")
    next(reader)

    dados = None
    produtos = []
    for row in reader:
        if row[0] == pedido:
            if dados is None:
                dados = {
                    "Pedido":        row[0],
                    "NomeCliente":   row[5],
                    "Email":         row[6],
                    "DataCompra":    row[7],
                    "PrazoGarantia": row[8],
                    "Telefone":      row[9],
                    "ValorVenda":    row[10],
                    "Produtos":      [],
                }
            produtos.append({
                "NomeProduto":   row[1],
                "CodigoProduto": row[2],
                "Quantidade":    row[3],
                "Preco":         row[4],
            })
    if dados is None:
        raise ValueError(f"Nenhum pedido encontrado para: {pedido}")
    dados["Produtos"] = produtos

    # 2) Preenche o template
    tpl = Path(TEMPLATE_TXT)
    if not tpl.exists():
        raise FileNotFoundError(f"Template não encontrado: {TEMPLATE_TXT}")
    texto = substituir_texto(tpl.read_text("utf-8"), dados)

    # 3) Renderiza em BytesIO
    buffer = BytesIO()
    doc = SimpleDocTemplate(
        buffer,
        pagesize=letter,
        rightMargin=72, leftMargin=72,
        topMargin=72, bottomMargin=18,
    )

    styles = getSampleStyleSheet()
    title_style = ParagraphStyle("Title", fontName="Helvetica-Bold",
                                 fontSize=32, leading=36,
                                 alignment=TA_CENTER, spaceAfter=20)
    normal_style = ParagraphStyle("Normal", fontName="Helvetica",
                                  fontSize=12, leading=14,
                                  alignment=TA_LEFT, spaceAfter=12)

    story = [Paragraph("TERMO DE GARANTIA", title_style)]
    for line in texto.splitlines():
        clean = limpar_texto(line)
        if not clean:
            story.append(Spacer(1, 12))
        else:
            story.append(Paragraph(clean, normal_style))

    frame = Frame(doc.leftMargin, doc.bottomMargin, doc.width, doc.height, id="normal")

    # callback que desenha a marca d'água
    def draw_background(canvas, doc):
        w, h = letter
        canvas.drawImage(IMG_FUNDO, 0, 0, width=w, height=h, mask="auto")

    # aplicamos o template (não obrigatório, mas ok) e
    # passamos draw_background em ambos callbacks abaixo
    template = PageTemplate(id="background", frames=[frame], onPage=draw_background)
    doc.addPageTemplates([template])

    # >>> AQUI A GRANDE MUDANÇA: 
    # passamos draw_background em onFirstPage e onLaterPages
    doc.build(
        story,
        onFirstPage=draw_background,
        onLaterPages=draw_background,
    )

    pdf_bytes = buffer.getvalue()
    buffer.close()
    return pdf_bytes
