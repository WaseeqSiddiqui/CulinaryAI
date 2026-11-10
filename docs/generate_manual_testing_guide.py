from pathlib import Path
import re

from docx import Document
from docx.shared import Inches, Pt, RGBColor
from docx.oxml import OxmlElement
from docx.oxml.ns import qn
from docx.enum.table import WD_TABLE_ALIGNMENT, WD_CELL_VERTICAL_ALIGNMENT
from docx.enum.text import WD_ALIGN_PARAGRAPH

ROOT = Path(__file__).resolve().parent
SOURCE = ROOT / 'MANUAL_TESTING_GUIDE.md'
OUTPUT = ROOT / 'CulinaryAI_Manual_Testing_Guide.docx'


def build():
    doc = Document()
    section = doc.sections[0]
    section.page_width, section.page_height = Inches(8.5), Inches(11)
    section.top_margin, section.bottom_margin = Inches(.66), Inches(.65)
    section.left_margin = section.right_margin = Inches(.75)
    section.header_distance = section.footer_distance = Inches(.3)
    for name in ['Normal', 'Title', 'Subtitle', 'Heading 1', 'Heading 2', 'Heading 3']:
        style = doc.styles[name]
        style.font.name = 'Calibri'
        style.font.color.rgb = RGBColor(0, 0, 0)
    normal = doc.styles['Normal']
    normal.font.size = Pt(11)
    normal.paragraph_format.line_spacing = 1.03
    normal.paragraph_format.space_after = Pt(6)
    for name, size in [('Title', 25), ('Heading 1', 19), ('Heading 2', 12)]:
        style = doc.styles[name]
        style.font.size = Pt(size)
        style.paragraph_format.space_before = Pt(10 if name != 'Title' else 0)
        style.paragraph_format.space_after = Pt(5)
        style.paragraph_format.keep_with_next = True
    header = section.header.paragraphs[0]
    header.text = 'CulinaryAI   |   Manual testing'
    header.runs[0].font.size = Pt(9)
    footer = section.footer.paragraphs[0]
    footer.alignment = WD_ALIGN_PARAGRAPH.RIGHT
    footer.add_run('10 November 2026   |   ')
    field = OxmlElement('w:fldSimple')
    field.set(qn('w:instr'), 'PAGE')
    footer._p.append(field)
    for run in footer.runs:
        run.font.size = Pt(9)
    lines = SOURCE.read_text(encoding='utf-8').splitlines()
    i = 0
    while i < len(lines):
        line = lines[i].strip()
        i += 1
        if not line:
            continue
        if line == '<!-- page -->':
            doc.add_page_break()
        elif line.startswith('# '):
            doc.add_paragraph(line[2:], 'Title')
        elif line.startswith('## '):
            doc.add_paragraph(line[3:], 'Heading 1')
        elif line.startswith('### '):
            doc.add_paragraph(line[4:], 'Heading 2')
        elif line.startswith('|'):
            rows = [[c.strip() for c in line.strip('|').split('|')]]
            while i < len(lines) and lines[i].strip().startswith('|'):
                cells = [c.strip() for c in lines[i].strip().strip('|').split('|')]
                i += 1
                if all(re.fullmatch(r'[-: ]+', c) for c in cells):
                    continue
                rows.append(cells)
            table = doc.add_table(rows=0, cols=4)
            table.alignment = WD_TABLE_ALIGNMENT.CENTER
            table.autofit = False
            widths = [1.65, 1.15, 1.0, 3.2]
            for col, width in zip(table.columns, widths):
                col.width = Inches(width)
            for rindex, data in enumerate(rows):
                row = table.add_row()
                if rindex == 0:
                    repeat = OxmlElement('w:tblHeader')
                    row._tr.get_or_add_trPr().append(repeat)
                for cindex, (cell, text) in enumerate(zip(row.cells, data)):
                    cell.width = Inches(widths[cindex])
                    cell.vertical_alignment = WD_CELL_VERTICAL_ALIGNMENT.CENTER
                    cell.text = text
                    props = cell._tc.get_or_add_tcPr()
                    shade = OxmlElement('w:shd')
                    shade.set(qn('w:fill'), 'E8EDF2' if rindex == 0 else 'FFFFFF')
                    props.append(shade)
                    margins = OxmlElement('w:tcMar')
                    for edge in ['top', 'bottom', 'start', 'end']:
                        node = OxmlElement('w:' + edge)
                        node.set(qn('w:w'), '100')
                        node.set(qn('w:type'), 'dxa')
                        margins.append(node)
                    props.append(margins)
                    borders = OxmlElement('w:tcBorders')
                    for edge in ['top', 'left', 'bottom', 'right']:
                        border = OxmlElement('w:' + edge)
                        for key, value in [('val', 'single'), ('sz', '4'), ('color', 'D9D9D9')]:
                            border.set(qn('w:' + key), value)
                        borders.append(border)
                    props.append(borders)
                    for p in cell.paragraphs:
                        p.paragraph_format.space_after = Pt(2)
                        for run in p.runs:
                            run.font.size = Pt(10)
                            run.bold = rindex == 0
            doc.add_paragraph()
        else:
            bullet = line.startswith('- ')
            p = doc.add_paragraph(style='List Bullet' if bullet else 'Normal')
            text = line[2:] if bullet else line
            label = next((label for label in ['Kahan:', 'Test:', 'Pass:'] if text.startswith(label)), None)
            if label:
                p.add_run(label).bold = True
                p.add_run(text[len(label):])
                p.paragraph_format.space_after = Pt(3)
                p.paragraph_format.keep_with_next = label != 'Pass:'
            else:
                p.add_run(text)
    doc.core_properties.title = 'CulinaryAI manual testing guide'
    doc.core_properties.subject = 'Manual feature checks excluding automated purchasing and checkout'
    doc.core_properties.author = 'CulinaryAI project'
    doc.save(OUTPUT)
    print(OUTPUT)


if __name__ == '__main__':
    build()
