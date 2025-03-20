import re
import csv
import requests
import smtplib
import os
from email.mime.multipart import MIMEMultipart
from email.mime.text import MIMEText
from email.mime.base import MIMEBase
from email import encoders
from reportlab.lib.pagesizes import letter
from reportlab.lib.styles import getSampleStyleSheet, ParagraphStyle
from reportlab.lib.enums import TA_CENTER, TA_LEFT
from reportlab.platypus import SimpleDocTemplate, Paragraph, Spacer, Frame, PageTemplate

def substituir_texto(template, dados):
    for chave, valor in dados.items():
        placeholder = f'{{{{{chave}}}}}'
        if isinstance(valor, list):
            valor = "\n".join([str(item) for item in valor])
        template = template.replace(placeholder, valor)
    return template

def limpar_texto(texto):
    return re.sub(r'[^\x20-\x7E\u00A0-\u024F]', '', texto).strip()

def criar_pdf_com_marca_dagua(texto, output_pdf, imagem_fundo):
    def draw_background(canvas, doc):
        width, height = letter
        canvas.drawImage(imagem_fundo, 0, 0, width=width, height=height, mask='auto')

    doc = SimpleDocTemplate(output_pdf, pagesize=letter,
                            rightMargin=72, leftMargin=72,
                            topMargin=72, bottomMargin=18)

    styles = getSampleStyleSheet()

    title_style = ParagraphStyle(
        name='Title',
        fontName="Helvetica-Bold",
        fontSize=32,
        leading=36,
        alignment=TA_CENTER,
        spaceAfter=20,
        textColor="black",
    )

    bold_style = ParagraphStyle(
        name='Bold',
        fontName="Helvetica-Bold",
        fontSize=12,
        leading=14,
        alignment=TA_LEFT,
        spaceAfter=12,
    )

    normal_style = ParagraphStyle(
        name='Normal',
        fontName="Helvetica",
        fontSize=12,
        leading=14,
        alignment=TA_LEFT,
        spaceAfter=12,
    )

    story = []
    story.append(Paragraph("TERMO DE GARANTIA", title_style))

    lines = texto.splitlines()
    for line in lines:
        line = limpar_texto(line)
        if line.startswith("Antonella Gold - Semijoias,"):
            partes = line.split("Antonella Gold - Semijoias,", 1)
            story.append(Paragraph(f"<b>Antonella Gold - Semijoias,</b>{partes[1]}", normal_style))
        elif line in ["Cuidados e Dicas de Preservação das Semijoias", "Contato para Assistência:", "Observações Adicionais:"] or line.startswith("* A garantia é válida apenas para o primeiro comprador"):
            story.append(Paragraph(line, bold_style))
        elif any(line.startswith(prefix) for prefix in [
            "1. Evite contato com Produtos Químicos:",
            "2. Guarde Separadamente:",
            "3. Retire Antes de Atividades Físicas:",
            "4. Limpeza Regular:",
            "5. Evite a Exposição Prolongada ao Sol:",
            "6. Evite o contato excessivo com água:"
        ]):
            partes = line.split(':', 1)
            if len(partes) == 2:
                story.append(Paragraph(f"<b>{partes[0]}:</b>{partes[1]}", normal_style))
            else:
                story.append(Paragraph(line, normal_style))
        elif line == "":
            story.append(Spacer(1, 12))
        else:
            story.append(Paragraph(line, normal_style))

    frame = Frame(doc.leftMargin, doc.bottomMargin, doc.width, doc.height, id='normal')
    template = PageTemplate(id='background', frames=frame, onPage=draw_background)
    doc.addPageTemplates([template])
    doc.build(story, onFirstPage=draw_background, onLaterPages=draw_background)

def enviar_email(destinatario, assunto, corpo_html, anexo):
    smtp_server = "smtp.gmail.com"
    smtp_port = 587
    smtp_user = os.getenv("email_smtp")
    smtp_password = os.getenv("pass_smtp")

    msg = MIMEMultipart()
    msg['From'] = smtp_user
    msg['To'] = destinatario
    msg['Subject'] = assunto

    msg.attach(MIMEText(corpo_html, 'html'))

    with open(anexo, "rb") as attachment:
        part = MIMEBase('application', 'octet-stream')
        part.set_payload(attachment.read())
        encoders.encode_base64(part)
        part.add_header('Content-Disposition', f'attachment; filename={anexo}')
        msg.attach(part)

    try:
        server = smtplib.SMTP(smtp_server, smtp_port)
        server.starttls()
        server.login(smtp_user, smtp_password)
        text = msg.as_string()
        server.sendmail(smtp_user, destinatario, text)
        server.quit()
        print(f"E-mail enviado com sucesso para {destinatario}")
    except Exception as e:
        print(f"Falha ao enviar e-mail: {e}")

def main():
    # Ajuste o link da planilha de dados se desejar
    url = "https://docs.google.com/spreadsheets/d/1Sdp3IUc-pOoFhuHgWhNnqqwFoaJbHxreYQHg_ySt6FQ/export?format=csv"
    response = requests.get(url)
    response_content = response.content.decode('utf-8')

    csv_data = csv.reader(response_content.splitlines(), delimiter=',')
    headers = next(csv_data)  # Captura os cabeçalhos do CSV

    pedidos = {}

    for row in csv_data:
        pedido = row[0]
        produto = row[1]
        codigo = row[2]
        quantidade = row[3]
        preco = row[4]
        nome_cliente = row[5]
        email = row[6]
        data_compra = row[7]
        prazo_garantia = row[8]
        telefone = row[9]

        if pedido not in pedidos:
            pedidos[pedido] = {
                "Pedido": pedido,
                "NomeCliente": nome_cliente,
                "Email": email,
                "DataCompra": data_compra,
                "PrazoGarantia": prazo_garantia,
                "Telefone": telefone,
                "Produtos": []
            }

        pedidos[pedido]["Produtos"].append({
            "NomeProduto": produto,
            "CodigoProduto": codigo,
            "Quantidade": quantidade,
            "Preco": preco
        })

    for pedido, dados in pedidos.items():
        pdf_name = f"garantia_{dados['NomeCliente'].replace(' ', '_')}_{pedido}.pdf"
        # Ajuste o caminho local, pois no Lambda os arquivos ficam em /var/task/
        template_path = "/var/task/template-garantia.txt"
        image_path = "/var/task/logo-backgroud.png"

        with open(template_path, "r", encoding="utf-8") as template_file:
            template_pdf = template_file.read()

        if not dados['Email']:
            # Se não tiver email, remove a linha "Email: {{Email}}\n"
            template_pdf = template_pdf.replace("Email: {{Email}}\n", "")

        texto_pdf = substituir_texto(template_pdf, dados)

        criar_pdf_com_marca_dagua(texto_pdf, pdf_name, image_path)
        print(f"PDF gerado: {pdf_name}")

        if dados['Email']:
            corpo_html = f"""
            <p>Olá <b>{dados['NomeCliente']}</b>,</p>
            <p>Muito obrigado por sua confiança e preferência!</p>
            <p>Segue o Termo de Garantia em anexo, com detalhes do seu pedido.</p>
            <p>Atenciosamente,<br>
            <b>Antonella Gold - Semijoias</b></p>
            """
            assunto = "Antonella Gold - Semijoias - Termo de Garantia"
            enviar_email(dados['Email'], assunto, corpo_html, pdf_name)

def lambda_handler(event, context):
    main()
    return {
        'statusCode': 200,
        'body': 'Garantia gerada com sucesso!'
    }
