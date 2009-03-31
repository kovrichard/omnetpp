package org.omnetpp.runtimeenv.widgets;

import org.eclipse.swt.graphics.Color;


/**
 * Clients may implement the TextViewerContent interface to provide a 
 * content for the TextViewer widget.
 */
public interface TextViewerContent {
    /**
     * Return the number of characters in the content.
     */
    public int getCharCount();

    /**
     * Return the line at the given line index without delimiters.
     * <p>
     *
     * @param lineIndex index of the line to return. Does not include 
     *	delimiters of preceding lines. Index 0 is the first line of the 
     * 	content.
     * @return the line text without delimiters
     */
    public String getLine(int lineIndex);

    /**
     * Return the line index at the given character offset.
     * <p>
     *
     * @param offset offset of the line to return. The first character of the 
     * 	document is at offset 0.  An offset of getLength() is valid and should 
     *	answer the number of lines. 
     * @return the line index. The first line is at index 0.  If the character 
     * 	at offset is a delimiter character, answer the line index of the line 
     * 	that is delimited. 
     * 	For example, if text = "\r\n\r\n", and delimiter = "\r\n", then:
     * <ul>
     * <li>getLineAtOffset(0) == 0
     * <li>getLineAtOffset(1) == 0
     * <li>getLineAtOffset(2) == 1
     * <li>getLineAtOffset(3) == 1
     * <li>getLineAtOffset(4) == 2
     * </ul>
     */
    public int getLineAtOffset(int offset);

    /**
     * Return the number of lines.  Should answer 1 when no text is specified.
     * The  TextViewer widget relies on this behavior for drawing the cursor.
     * <p>
     *
     * @return the number of lines.  For example:
     * <ul>
     * <li>	text value ==> getLineCount		
     * <li>	null ==> 1		
     * <li>	"" ==> 1		
     * <li>	"a\n" ==> 2			
     * <li>	"\n\n" ==> 3			
     * </ul>
     */
    public int getLineCount();

    /**
     * Return the character offset of the first character of the given line.
     * <p>
     * <b>NOTE:</b> When there is no text (i.e., no lines), getOffsetAtLine(0) 
     * is a valid call that should return 0.
     * </p>
     *
     * @param lineIndex index of the line. The first line is at index 0.
     * @return offset offset of the first character of the line. The first 
     * 	character of the document is at offset 0.  The return value should 
     * 	include line delimiters.  
     * 	For example, if text = "\r\ntest\r\n" and delimiter = "\r\n", then:
     * <ul>
     * <li>getOffsetAtLine(0) == 0
     * <li>getOffsetAtLine(1) == 2
     * <li>getOffsetAtLine(2) == 8
     * </ul>
     */
    public int getOffsetAtLine(int lineIndex);

    /**
     * Returns a string representing the content at the given range.
     * <p>
     *
     * @param start the start offset of the text to return. Offset 0 is the 
     * 	first character of the document.
     * @param length the length of the text to return
     * @return the text at the given range
     */
    public String getTextRange(int start, int length);

    /**
     * Return the color for the specified line.
     * 
     * @return the color, or null to indicate using the default foreground color
     */
    public Color getLineColor(int lineIndex);

    /**
     * Called by TextViewer to add itself as an Observer to content changes.
     * See TextChangeListener for a description of the listener methods that
     * are called when text changes occur.
     * <p>
     *
     * @param listener the listener
     * @exception IllegalArgumentException <ul>
     *    <li>ERROR_NULL_ARGUMENT when listener is null</li>
     * </ul>
     */
    public void addTextChangeListener(TextChangeListener listener);

    /**
     * Remove the specified text changed listener.
     * <p>
     *
     * @param listener the listener which should no longer be notified
     * 
     * @exception IllegalArgumentException <ul>
     *    <li>ERROR_NULL_ARGUMENT when listener is null</li>
     * </ul>
     */
    public void removeTextChangeListener(TextChangeListener listener);
}
