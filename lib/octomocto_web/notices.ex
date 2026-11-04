defmodule OctomoctoWeb.Notices do
  @moduledoc """
  The `on_mount` hook that keeps the queue of the notices of the user or
  the guest of the page (see `Octomocto.Notices`) in the `:notices`
  assign of a LiveView: the first one shows, the others wait. The queue is
  in the memory of the page only. It runs after the hooks that assign
  `:current_scope` and `:guest_id`.

  The page renders the first notice with `notice/1`. A click on one of its
  buttons sends the `"notice_action"` event, which this hook handles: it
  closes the notice on all pages of the recipient, and goes to the `:href` of
  the button, if any.
  """
  use Phoenix.Component

  import Phoenix.LiveView

  alias Octomocto.Notices

  def on_mount(:default, _params, _session, socket) do
    socket = assign(socket, notices: [])

    case recipient(socket.assigns) do
      nil ->
        {:cont, socket}

      recipient ->
        if connected?(socket), do: Notices.subscribe(recipient)

        {:cont,
         socket
         |> assign(notice_recipient: recipient)
         |> attach_hook(:notices, :handle_info, &handle_info/2)
         |> attach_hook(:notices, :handle_event, &handle_event/3)}
    end
  end

  defp recipient(%{current_scope: %{user: %{id: user_id}}}), do: {:user, user_id}
  defp recipient(%{guest_id: guest_id}) when is_binary(guest_id), do: {:guest, guest_id}
  defp recipient(_assigns), do: nil

  defp handle_info({:notice, notice}, socket) do
    cond do
      Enum.any?(socket.assigns.notices, &(&1.id == notice.id)) ->
        {:halt, socket}

      notice.expires_at == nil ->
        {:halt, update(socket, :notices, &(&1 ++ [notice]))}

      (left = notice.expires_at - System.system_time(:millisecond)) > 0 ->
        Process.send_after(self(), {:notice_expired, notice.id}, left)
        {:halt, update(socket, :notices, &(&1 ++ [notice]))}

      true ->
        {:halt, socket}
    end
  end

  defp handle_info({tag, id}, socket) when tag in [:notice_dismissed, :notice_expired] do
    {:halt, update(socket, :notices, fn notices -> Enum.reject(notices, &(&1.id == id)) end)}
  end

  defp handle_info(_message, socket), do: {:cont, socket}

  defp handle_event("notice_action", %{"id" => id, "action" => action_id}, socket) do
    with %{} = notice <- Enum.find(socket.assigns.notices, &(&1.id == id)),
         %{} = action <- Enum.find(notice.actions, &(&1.id == action_id)) do
      Notices.dismiss(socket.assigns.notice_recipient, id)
      if action.href, do: {:halt, redirect(socket, to: action.href)}, else: {:halt, socket}
    else
      _ -> {:halt, socket}
    end
  end

  defp handle_event(_event, _params, socket), do: {:cont, socket}

  @doc """
  The first notice of the queue: its text and its buttons. The first button
  is the main one. `waiting` is the number of the other notices.
  """
  attr :notice, :map, required: true
  attr :waiting, :integer, default: 0

  def notice(assigns) do
    ~H"""
    <div
      id={"notice-#{@notice.id}"}
      phx-mounted={
        Phoenix.LiveView.JS.transition(
          {"ease-out duration-300", "opacity-0 -translate-y-1", "opacity-100 translate-y-0"}
        )
      }
      class="flex min-w-0 items-center gap-3"
    >
      <p class="min-w-0 truncate font-medium">{@notice.text}</p>
      <div class="flex shrink-0 items-center gap-1">
        <button
          :for={{action, i} <- Enum.with_index(@notice.actions)}
          id={"notice-#{@notice.id}-#{action.id}"}
          type="button"
          phx-click="notice_action"
          phx-value-id={@notice.id}
          phx-value-action={action.id}
          class={[
            "cursor-pointer rounded-full px-3 py-0.5 text-xs font-medium transition active:scale-95",
            if(i == 0,
              do: "bg-white text-octo-indigo shadow-sm hover:bg-white/90",
              else: "text-white/80 hover:bg-white/10 hover:text-white"
            )
          ]}
        >
          {action.label}
        </button>
      </div>
      <span :if={@waiting > 0} class="shrink-0 text-xs tabular-nums text-white/60">
        +{@waiting}
      </span>
    </div>
    """
  end
end
