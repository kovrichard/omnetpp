/*--------------------------------------------------------------*
  Copyright (C) 2006-2008 OpenSim Ltd.

  This file is distributed WITHOUT ANY WARRANTY. See the file
  'License' for details on this and other legal matters.
*--------------------------------------------------------------*/

package org.omnetpp.ned.editor.graph.parts;

import java.util.ArrayList;
import java.util.HashMap;
import java.util.List;
import java.util.Map;

import org.eclipse.draw2d.ConnectionAnchor;
import org.eclipse.draw2d.IFigure;
import org.eclipse.draw2d.PositionConstants;
import org.eclipse.draw2d.geometry.Point;
import org.eclipse.gef.CompoundSnapToHelper;
import org.eclipse.gef.ConnectionEditPart;
import org.eclipse.gef.EditPart;
import org.eclipse.gef.EditPolicy;
import org.eclipse.gef.GraphicalEditPart;
import org.eclipse.gef.MouseWheelHelper;
import org.eclipse.gef.SnapToGeometry;
import org.eclipse.gef.SnapToHelper;
import org.eclipse.gef.editparts.ViewportMouseWheelHelper;
import org.eclipse.gef.editpolicies.SnapFeedbackPolicy;
import org.omnetpp.common.displaymodel.IDisplayString.Prop;
import org.omnetpp.figures.anchors.CompoundModuleGateAnchor;
import org.omnetpp.figures.anchors.GateAnchor;
import org.omnetpp.ned.editor.graph.figures.CompoundModuleFigureEx;
import org.omnetpp.ned.editor.graph.parts.policies.CompoundModuleLayoutEditPolicy;
import org.omnetpp.ned.editor.graph.properties.util.TypeNameValidator;
import org.omnetpp.ned.model.INedElement;
import org.omnetpp.ned.model.ex.CompoundModuleElementEx;
import org.omnetpp.ned.model.ex.ConnectionElementEx;
import org.omnetpp.ned.model.pojo.TypesElement;

/**
 * Edit part controlling the appearance of the compound module figure. Note that this
 * editpart handles its own connection part registry and does not use the global registry
 *
 * @author rhornig
 */
public class CompoundModuleEditPart extends ModuleEditPart {

    // stores  the connection model - connection editPart mapping for the compound module
    private final Map<Object, ConnectionEditPart> modelToConnectionPartsRegistry = new HashMap<Object, ConnectionEditPart>();

    @Override
    public void activate() {
        super.activate();
        renameValidator = new TypeNameValidator(getCompoundModuleModel());
    }

    @Override
    protected void createEditPolicies() {
        super.createEditPolicies();
        installEditPolicy(EditPolicy.LAYOUT_ROLE, new CompoundModuleLayoutEditPolicy());
        installEditPolicy("Snap Feedback", new SnapFeedbackPolicy());
    }

    /**
     * Creates and returns a new module figure
     */
    @Override
    protected IFigure createFigure() {
        return new CompoundModuleFigureEx();
    }

    /**
     * Convenience method to return the figure object with the correct type
     */
    public CompoundModuleFigureEx getCompoundModuleFigure() {
        return (CompoundModuleFigureEx) getFigure();
    }

    /**
     * Convenience method to return the model object with the correct type
     */
    public CompoundModuleElementEx getCompoundModuleModel() {
        return (CompoundModuleElementEx)getModel();
    }

    @Override
    public IFigure getContentPane() {
        return getCompoundModuleFigure().getSubmoduleLayer();
    }

    // overridden so submodules are added to the contentPane while TypesEditPart is never added as a child
    // TypesEdit part is always associated with the innerTypesCompartment of the CompoundModuleFigure
    @Override
    protected void addChildVisual(EditPart childEditPart, int index) {
        IFigure child = ((GraphicalEditPart)childEditPart).getFigure();
        if (!(childEditPart instanceof TypesEditPart))
            getContentPane().add(child);
    }

    // overridden so child figures are always removed from their parent
    @Override
    protected void removeChildVisual(EditPart childEditPart) {
        IFigure child = ((GraphicalEditPart)childEditPart).getFigure();
        // never throw away the types compartment figure
        if (!(childEditPart instanceof TypesEditPart))
            child.getParent().remove(child);
    }

    @Override
    @SuppressWarnings("unchecked")
    public Object getAdapter(Class key) {
        if (key == MouseWheelHelper.class) return new ViewportMouseWheelHelper(this);
        // snap to grid/guide adaptor
        if (key == SnapToHelper.class) {
            List<SnapToGeometry> snapStrategies = new ArrayList<SnapToGeometry>();
            Boolean val = (Boolean) getViewer().getProperty(SnapToGeometry.PROPERTY_SNAP_ENABLED);
            if (val) snapStrategies.add(new SnapToGeometry(this));

            if (snapStrategies.size() == 0) return null;
            if (snapStrategies.size() == 1) return snapStrategies.get(0);

            SnapToHelper ss[] = new SnapToHelper[snapStrategies.size()];
            for (int i = 0; i < snapStrategies.size(); i++)
                ss[i] = snapStrategies.get(i);
            return new CompoundSnapToHelper(ss);
        }

        return super.getAdapter(key);
    }

    @Override
    protected List<INedElement> getModelChildren() {
        List<INedElement> result = new ArrayList<INedElement>();
        // add the innerTypes element (if exists)
        TypesElement typesElement = getCompoundModuleModel().getFirstTypesChild();
        if (typesElement != null)
            result.add(typesElement);

        // return all submodule including inherited ones
        result.addAll(getCompoundModuleModel().getSubmodules());
    	return result;
    }

    /**
     * Returns a list of connections for which this is the srcModule.
     */
    @Override
    protected List<ConnectionElementEx> getModelSourceConnections() {
        return getCompoundModuleModel().getSrcConnections();
    }

    /**
     * Returns a list of connections for which this is the destModule.
     */
    @Override
    protected List<ConnectionElementEx> getModelTargetConnections() {
        return getCompoundModuleModel().getDestConnections();
    }

    /**
     * Updates the visual aspect of this compound module
     */
    @Override
    protected void refreshVisuals() {
        super.refreshVisuals();
        // define the properties that determine the visual appearance
        CompoundModuleFigureEx compoundModuleFigure = getCompoundModuleFigure();
        CompoundModuleElementEx compoundModuleModel = getCompoundModuleModel();
        compoundModuleFigure.setName(compoundModuleModel.getName());
    	compoundModuleFigure.setDisplayString(compoundModuleModel.getDisplayString());
    }

	/**
	 * Returns whether the compound module is selectable (mouse is over the bordering area)
	 * for the selection tool based on the current mouse target coordinates.
	 * Coordinates are viewport relative.
	 */
	public boolean isOnBorder(int x, int y) {
		return getCompoundModuleFigure().isOnBorder(x, y);
	}

	/**
	 * Compute the source connection anchor to be assigned based on the current mouse
	 * location and available gates.
	 * @param p current mouse coordinates
	 * @return The selected connection anchor
	 */
	@Override
    public ConnectionAnchor getConnectionAnchorAt(Point p) {
        return new CompoundModuleGateAnchor(getFigure());
	}

	/**
	 * Returns a connection anchor registered for the given gate
	 */
	@Override
    public GateAnchor getConnectionAnchor(ConnectionElementEx connection, String gate) {
	    CompoundModuleGateAnchor gateAnchor = new CompoundModuleGateAnchor(getFigure());
        gateAnchor.setEdgeConstraint(getRoutingConstraintPosition(connection.getDisplayString().getAsString(Prop.ROUTING_CONSTRAINT)));
        return gateAnchor;
	}

    private int getRoutingConstraintPosition(String routingConstraint) {
        int position;
        if (routingConstraint == null || routingConstraint.equals("a"))
            position = PositionConstants.NSEW;
        else if (routingConstraint.equals("n"))
            position = PositionConstants.NORTH;
        else if (routingConstraint.equals("s"))
            position = PositionConstants.SOUTH;
        else if (routingConstraint.equals("e"))
            position = PositionConstants.EAST;
        else if (routingConstraint.equals("w"))
            position = PositionConstants.WEST;
        else
            // default;
            position = PositionConstants.NSEW;
        return position;
    }

    /**
     * Returns the current scaling factor of the compound module
     */
    @Override
    public float getScale() {
        return ((CompoundModuleElementEx)getModel()).getDisplayString().getScale();
    }

    @Override
    public CompoundModuleEditPart getCompoundModulePart() {
        return this;
    }

    /**
     * Returns the MAP that contains the connection model - controller associations
     */
    public Map<Object, ConnectionEditPart> getModelToConnectionPartsRegistry() {
        return modelToConnectionPartsRegistry;
    }

    /* (non-Javadoc)
     * @see org.omnetpp.ned.editor.graph.edit.NedEditPart#getTypeNameForDblClickOpen()
     * open the first base component for double click
     */
    @Override
    protected INedElement getNedElementToOpen() {
        return getCompoundModuleModel().getFirstExtendsRef();
    }
}
