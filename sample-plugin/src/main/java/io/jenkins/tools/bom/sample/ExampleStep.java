package io.jenkins.tools.bom.sample;

import hudson.Extension;
import hudson.model.TaskListener;
import java.util.Collections;
import java.util.Set;
import org.jenkinsci.plugins.workflow.steps.Step;
import org.jenkinsci.plugins.workflow.steps.StepContext;
import org.jenkinsci.plugins.workflow.steps.StepDescriptor;
import org.jenkinsci.plugins.workflow.steps.StepExecution;
import org.jenkinsci.plugins.workflow.steps.SynchronousStepExecution;
import org.kohsuke.stapler.DataBoundConstructor;
import org.kohsuke.stapler.DataBoundSetter;

public final class ExampleStep extends Step {

    @DataBoundSetter public String x;

    @DataBoundConstructor public ExampleStep() {}

    @Override public StepExecution start(StepContext context) throws Exception {
        return new Execution(context, x);
    }

    private static final class Execution extends SynchronousStepExecution<Void> {

        private final String x;

        Execution(StepContext context, String x) {
            super(context);
            this.x = x;
        }
        
        @Override protected Void run() throws Exception {
            getContext().get(TaskListener.class).getLogger().println("Ran on " + x + "!");
            return null;
        }

    }

    @Extension public static final class DescriptorImpl extends StepDescriptor {

        @Override public String getFunctionName() {
            return "example";
        }

        @Override public Set<? extends Class<?>> getRequiredContext() {
            return Collections.singleton(TaskListener.class);
        }

    }

}
