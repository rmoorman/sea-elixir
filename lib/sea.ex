defmodule Sea do
  @moduledoc ~S"""
  Side-effect abstraction - put your synchronous side-effects in order.

  Sea consists of following modules:

  - `Sea.Signal` - defines signal that will get emitted to defined observers
  - `Sea.Observer` - Defines observer capable of handling signals emitted to it

  ## Usage

  ### Basic example

  In Sea, you define signal and a bunch of observers that get called upon signal emission:

      defmodule SomeSignal do
        use Sea.Signal

        emit_to SomeObserver

        defstruct [:some_data]
      end

      defmodule SomeObserver do
        use Sea.Observer

        @impl true
        def handle_signal(%SomeSignal{some_data: some_data}) do
          IO.puts("Acting upon some signal with data: #{inspect(some_data)}")
        end
      end

      SomeSignal.emit(%SomeSignal{some_data: "foo"})

  ### Signal-Observer naming convention

  In order to simplify working with growing number of signals and their observers scattered across
  project modules, you may define observers like this:

      defmodule MyApp.X.SomeSignal do
        use Sea.Signal

        emit_within MyApp.{Y, Z}

        defstruct [:some_data]
      end

      defmodule MyApp.Y.SomeObserver do
        use Sea.Observer

        @impl true
        def handle_signal(%MyApp.X.SomeSignal{some_data: some_data}) do
          IO.puts("Y acting upon some signal with data: #{inspect(some_data)}")
        end
      end

      defmodule MyApp.Z.SomeObserver do
        use Sea.Observer

        @impl true
        def handle_signal(%MyApp.X.SomeSignal{some_data: some_data}) do
          IO.puts("Z acting upon some signal with data: #{inspect(some_data)}")
        end
      end

      Sea.Signal.emit(%MyApp.X.SomeSignal{some_data: "foo"})

  ### Decoupling contexts

  Let's assume you have a service that causes several side-effects across the system:

      defmodule MyApp.Sales.CreateInvoiceService do
        alias MyApp.Repo
        alias MyApp.Sales.Invoice
        alias MyApp.{Analytics, Customers, Inventory}

        def call(product_id, customer_id) do
          invoice_attrs = [
            product_id: product_id,
            customer_id: customer_id
          ]

          Repo.transaction(fn ->
            invoice =
              invoice_attrs
              |> Invoice.changeset()
              |> Repo.insert()

            Analytics.increase_invoice_count()
            Customers.mark_customer_active(customer_id)
            Inventory.decrease_stock(product_id)
          end)
        end
      end

  As you can see, each external side-effect is directly invoked from the original service. This code
  is a great case to introduce the benefits of Sea.

  Let's start by introducing a signal capable of building itself from our invoice struct:

      defmodule MyApp.Sales.InvoiceCreatedSignal do
        use Sea.Signal

        emit_within MyApp.{Analytics, Customers, Inventory}

        defstruct [:customer_id, :product_id]

        def build(%MyApp.Sales.Invoice{customer_id: customer_id, product_id: product_id}) do
          %__MODULE__{
            customer_id: customer_id,
            product_id: product_id
          }
        end
      end

  Now let's call it from the service instead of calling all these external modules:

      defmodule MyApp.Sales.CreateInvoiceService do
        alias MyApp.Repo
        alias MyApp.Sales.{Invoice, InvoiceCreatedSignal}

        def call(product_id, customer_id) do
          invoice_attrs = [
            product_id: product_id,
            customer_id: customer_id
          ]

          Repo.transaction(fn ->
            invoice =
              invoice_attrs
              |> Invoice.changeset()
              |> Repo.insert()

            InvoiceCreatedSignal.emit(invoice)
          end)
        end
      end

  And finally, let's ensure that observers are in place to handle the external side-effects:

      defmodule MyApp.Analytics.InvoiceCreatedObserver do
        use Sea.Observer

        def handle_signal(signal) do
          # ...
        end
      end

      defmodule MyApp.Customers.InvoiceCreatedObserver do
        use Sea.Observer

        def handle_signal(signal) do
          # ...
        end
      end

      defmodule MyApp.Inventory.InvoiceCreatedObserver do
        use Sea.Observer

        def handle_signal(signal) do
          # ...
        end
      end

  That's it - the side-effect has been properly facilitated.

  ## Testing

  With Sea acting as your hub for distributing side-effects across modules you may have two main
  testing scenarios involving signals:

  1. **Signals disabled** for unit testing purposes. In such scenario you want your signal emission
     stubbed away from the logic of unit that normally does emit it. In some of those cases, you
     would still like to verify that the signal does get emitted without causing side-effects.

  2. **Signals enabled** for testing integration between contexts. In such scenario you want your
     signal to behave like it does in final product - to trigger observers all over the place and
     cause all the side-effects so you can check if they behave properly in integration.

  Ideally, you'd like these two kinds of tests to execute asynchronously. And perhaps you'd like to
  do some other custom mocking or stubbing on top of the signals.

  Picking up on the previous example, you could want to ensure that `CreateInvoiceService` can be
  tested in isolation from side-effects in `Analytics`, `Customers` and `Inventory` contexts, but at
  the same time to also create an integration test which does opt-in for the side-effects.

  ### Signal mocking with Mox

  Sea covers all of these cases by leveraging the excellent `Mox` library to define mocks on top of
  signals. It also provides `Sea.SignalMocking` module with helpers useful to minimize the
  boilerplate around testing and mocking signals.

  In order to mock signals, go through the following procedure:

  1. Add `Mox` to the project.
  2. Add config that by default points to `SomeSignal`, but to `SomeSignal.Mock` in test env.
  3. Call the signal module fetched from config instead of `SomeSignal` in your app code.
  4. Define mock by calling `Sea.SignalMocking.defsignalmock/1` in test helper or support script.
  5. Call `Sea.SignalMocking.enable_signal/1` or `Sea.SignalMocking.disable_signal/1`in test cases.

  By leveraging Mox, Sea gives you all the options for testing and verifying mocks that Mox does.
  In order to do so, assume the following module naming convention:

  - `SomeSignal` is your actual signal implementation
  - `SomeSignal.Mock` is the mocked version of it
  - `SomeSignal.Behaviour` is the behaviour implemented by both of the above

  This means that you may do the following in your test case in order to ensure that `SomeSignal`
  does get called with specific input without it causing side-effects:

      disable_signal(SomeSignal)
      expect(SomeSignal.Mock, :emit, fn %SomeInput{} -> :ok end)

      # ...
      # call & test the code which emits SomeSignal
      # ...

      verify!(SomeSignal.Mock)

  """
end
