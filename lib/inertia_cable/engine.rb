module InertiaCable
  class Engine < ::Rails::Engine
    isolate_namespace InertiaCable

    initializer "inertia_cable.broadcastable" do
      ActiveSupport.on_load(:active_record) do
        include InertiaCable::Broadcastable
      end
    end

    initializer "inertia_cable.controller_helpers" do
      ActiveSupport.on_load(:action_controller) do
        include InertiaCable::ControllerHelpers
      end
    end
  end
end
