package com.simulcraft.test.gui.access;

import junit.framework.Assert;

import org.apache.commons.lang.ArrayUtils;
import org.eclipse.swt.graphics.Point;
import org.eclipse.swt.graphics.Rectangle;
import org.eclipse.swt.widgets.Control;
import org.eclipse.swt.widgets.Menu;
import org.eclipse.swt.widgets.Table;
import org.eclipse.swt.widgets.TableItem;
import org.eclipse.swt.widgets.Text;

import com.simulcraft.test.gui.core.InUIThread;
import com.simulcraft.test.gui.core.NotInUIThread;

public class TableItemAccess extends ClickableWidgetAccess
{
	public TableItemAccess(TableItem widget) {
		super(widget);
	}
	
	public TableItem getTableItem() {
		return (TableItem)widget;
	}

	@InUIThread
	public TableAccess getTable() {
	    return (TableAccess) createAccess(getTableItem().getParent());
	}

	@InUIThread
	public TableItemAccess reveal() {
		Table table = getTableItem().getParent();
		int myIndex = ArrayUtils.indexOf(table.getItems(), getTableItem());
		table.setTopIndex(myIndex); // scroll there
		return this;
	}

	@Override
	protected Point getAbsolutePointToClick() {
	    Point point = getTableItem().getParent().toDisplay(getCenter(getTableItem().getBounds()));
        Assert.assertTrue("point to click is scrolled out", getTable().getAbsoluteBounds().contains(point));
        Assert.assertTrue("column has zero width", getTableItem().getBounds().width > 0);
        return point;
	}

	/**
     * Useful for selecting a table item without incidentally activating its cell editor.
     */
    @InUIThread
    public void clickLeftEdge() {
        Rectangle bounds = getTableItem().getBounds();
        Point point = getTableItem().getParent().toDisplay(new Point(1, bounds.y+bounds.height/2));
        Assert.assertTrue("point to click is scrolled out", getTable().getAbsoluteBounds().contains(point));
        Assert.assertTrue("column has zero width", bounds.width > 0);
        clickAbsolute(LEFT_MOUSE_BUTTON, point);
    }
    

	@Override
	protected Menu getContextMenu() {
		return (Menu)getTableItem().getParent().getMenu();
	}
	
    @InUIThread
    public void ensureChecked(boolean state) {
        if (getTableItem().getChecked() != state) {
            click();
            pressKey(' ');
        }
    }
	
    @InUIThread
    public void clickColumn(int index) {
        Point point = getTableItem().getParent().toDisplay(getCenter(getTableItem().getTextBounds(index)));
        Assert.assertTrue("point to click is scrolled out", getTable().getAbsoluteBounds().contains(point));
        clickAbsolute(LEFT_MOUSE_BUTTON, point);
    }

    @NotInUIThread
    public TextAccess activateCellEditor() {
        Control oldFocusControl = getFocusControl().getControl();
        click();
        Control focusControl = getFocusControl().getControl();
        Assert.assertTrue("cell editor could not be activated", focusControl instanceof Text && oldFocusControl != focusControl);
        System.out.println(oldFocusControl.getClass().getSimpleName());
        return (TextAccess)createAccess(focusControl);
    }

    @NotInUIThread
    public TextAccess activateCellEditor(int index) {
        Control oldFocusControl = getFocusControl().getControl();
        clickColumn(index);
        Control focusControl = getFocusControl().getControl();
        Assert.assertTrue("cell editor could not be activated", focusControl instanceof Text && oldFocusControl != focusControl);
        System.out.println(oldFocusControl.getClass().getSimpleName());
        return (TextAccess)createAccess(focusControl);
    }
    
    @NotInUIThread
    public void clickAndTypeOver(String content) {
        TextAccess cellEditor = activateCellEditor();
        cellEditor.typeOver(content);
        cellEditor.pressEnter();
        //assertTextContent(Pattern.quote(content));  //XXX this would assume text gets stored "as is"
    }

    @NotInUIThread
    public void clickAndTypeOver(int index, String content) {
        TextAccess cellEditor = activateCellEditor(index);
        cellEditor.typeOver(content);
        cellEditor.pressEnter();
        //assertTextContent(index, Pattern.quote(content));  //XXX this would assume text gets stored "as is"
    }

    @InUIThread
    public void assertTextContent(String content) {
        Assert.assertTrue(getTableItem().getText().matches(content));
    }

    @InUIThread
    public void assertTextContent(int index, String content) {
        Assert.assertTrue(getTableItem().getText(index).matches(content));
    }

}

