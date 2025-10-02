#!/bin/bash

# Script to generate PNG/SVG diagrams from the Mermaid definitions in cmap_uml_diagrams.md
# Requires: npm install -g @mermaid-js/mermaid-cli

set -e

echo "🎯 CMAP UML Diagram Generator"
echo "==============================="

# Check if mmdc is installed
if ! command -v mmdc &> /dev/null; then
    echo "❌ mermaid-cli not found. Install with:"
    echo "   npm install -g @mermaid-js/mermaid-cli"
    exit 1
fi

# Create output directory
mkdir -p diagrams
cd diagrams

echo "📊 Extracting and generating diagrams..."

# Extract each mermaid diagram and generate images
awk '
/^```mermaid$/ { 
    in_mermaid = 1
    diagram_count++
    filename = "diagram_" diagram_count ".mmd"
    print "Extracting diagram " diagram_count " to " filename
    next
}
/^```$/ && in_mermaid { 
    in_mermaid = 0
    close(filename)
    system("mmdc -i " filename " -o diagram_" diagram_count ".png -t neutral -b white")
    system("mmdc -i " filename " -o diagram_" diagram_count ".svg -t neutral -b white")
    next
}
in_mermaid { 
    print > filename
}
' ../cmap_uml_diagrams.md

echo ""
echo "✅ Generated diagrams:"
ls -la *.png *.svg 2>/dev/null || echo "No files generated"

echo ""
echo "📁 Diagram mapping:"
echo "  diagram_1.* = Class Diagram - Core Components"
echo "  diagram_2.* = State Diagram - Connection Lifecycle"  
echo "  diagram_3.* = State Diagram - Pool Lifecycle"
echo "  diagram_4.* = Sequence Diagram - CheckOut Flow"
echo "  diagram_5.* = Sequence Diagram - Pool Clear"
echo "  diagram_6.* = Activity Diagram - Connection Establishment"
echo "  diagram_7.* = Component Diagram - System Integration"
echo "  diagram_8.* = Timing Diagram - Concurrent Operations"

echo ""
echo "🎉 Done! Open any .png or .svg file to view the diagrams."