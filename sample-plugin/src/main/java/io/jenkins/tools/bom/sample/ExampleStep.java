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

public final class ExampleStep extends Step {

    @DataBoundConstructor public ExampleStep() {}

    @Override public StepExecution start(StepContext context) throws Exception {
        return new Execution(context);
    }

    private static final class Execution extends SynchronousStepExecution<Void> {

        Execution(StepContext context) {
            super(context);
        }
        
        @Override protected Void run() throws Exception {
            getContext().get(TaskListener.class).getLogger().println("Ran example step!");
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
