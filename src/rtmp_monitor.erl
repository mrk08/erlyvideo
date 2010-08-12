%%% @author     Max Lapshin <max@maxidoors.ru> [http://erlyvideo.org]
%%% @copyright  2010 Max Lapshin
%%% @doc        RTMP socket monitor. Shutdown slow clients
%%% @reference  See <a href="http://erlyvideo.org/rtmp" target="_top">http://erlyvideo.org/rtmp</a> for more information.
%%% @end
%%%
%%% This file is part of erlang-rtmp.
%%% 
%%% erlang-rtmp is free software: you can redistribute it and/or modify
%%% it under the terms of the GNU General Public License as published by
%%% the Free Software Foundation, either version 3 of the License, or
%%% (at your option) any later version.
%%%
%%% erlang-rtmp is distributed in the hope that it will be useful,
%%% but WITHOUT ANY WARRANTY; without even the implied warranty of
%%% MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
%%% GNU General Public License for more details.
%%%
%%% You should have received a copy of the GNU General Public License
%%% along with erlang-rtmp.  If not, see <http://www.gnu.org/licenses/>.
%%%
%%%---------------------------------------------------------------------------------------
-module(rtmp_monitor).
-author('Max Lapshin <max@maxidoors.ru>').

-define(TIMEOUT, 1000).
-behaviour(gen_server).

-export([start_link/0, start_link/1]).

-record(rtmp_monitor, {
  threshold,
  timeout
}).

%% gen_server callbacks
-export([init/1, handle_call/3, handle_cast/2, handle_info/2, terminate/2, code_change/3]).

%%--------------------------------------------------------------------
%% @spec () -> {ok, Pid} | {error, Reason}
%%
%% @doc Called by a supervisor to start the listening process.
%% @end
%%----------------------------------------------------------------------
start_link() -> start_link([]).
start_link(Options) -> gen_server:start_link({local, ?MODULE}, ?MODULE, [Options], []).

%%----------------------------------------------------------------------
%% @spec (Port::integer()) -> {ok, State}           |
%%                            {ok, State, Timeout}  |
%%                            ignore                |
%%                            {stop, Reason}
%%
%% @doc Called by gen_server framework at process startup.
%%      Create listening socket.
%% @end
%%----------------------------------------------------------------------
init(Options) ->
  Timeout = proplists:get_value(timeout,Options,?TIMEOUT),
  Threshold = proplists:get_value(threshold,Options,5000),
  {ok, #rtmp_monitor{timeout = Timeout, threshold = Threshold}, Timeout}.


%%-------------------------------------------------------------------------
%% @spec (Request, From, State) -> {reply, Reply, State}          |
%%                                 {reply, Reply, State, Timeout} |
%%                                 {noreply, State}               |
%%                                 {noreply, State, Timeout}      |
%%                                 {stop, Reason, Reply, State}   |
%%                                 {stop, Reason, State}
%% @doc Callback for synchronous server calls.  If `{stop, ...}' tuple
%%      is returned, the server is stopped and `terminate/2' is called.
%% @end
%% @private
%%-------------------------------------------------------------------------

handle_call(Request, _From, State) ->
 {stop, {unknown_call, Request}, State}.

%%-------------------------------------------------------------------------
%% @spec (Msg, State) ->{noreply, State}          |
%%                      {noreply, State, Timeout} |
%%                      {stop, Reason, State}
%% @doc Callback for asyncrous server calls.  If `{stop, ...}' tuple
%%      is returned, the server is stopped and `terminate/2' is called.
%% @end
%% @private
%%-------------------------------------------------------------------------
handle_cast(_Msg, State) ->
  {stop, {unhandled_cast, _Msg}, State}.

%%-------------------------------------------------------------------------
%% @spec (Msg, State) ->{noreply, State}          |
%%                      {noreply, State, Timeout} |
%%                      {stop, Reason, State}
%% @doc Callback for messages sent directly to server's mailbox.
%%      If `{stop, ...}' tuple is returned, the server is stopped and
%%      `terminate/2' is called.
%% @end
%% @private
%%-------------------------------------------------------------------------
% 

handle_info(timeout, #rtmp_monitor{timeout = Timeout, threshold = Threshold} = State) ->
  Sockets = [Pid || {undefined,Pid,worker,_} <- supervisor:which_children(rtmp_socket_sup)],
  BrutalKill = lists:filter(fun(Pid) ->
    try element(2,process_info(Pid, message_queue_len)) of
      Length when is_number(Length) andalso is_number(Threshold) andalso Length > Threshold -> true;
      _Length -> false
    catch
      _Class:_Error -> false
    end
  end, Sockets),
  report_brutal_kill(BrutalKill),
  brutal_kill(BrutalKill),
  {noreply, State, Timeout};


handle_info(Message, State) ->
  {stop, {unhandled, Message}, State}.


report_brutal_kill([]) -> ok;
report_brutal_kill(BrutalKill) -> error_logger:error_msg("[RTMP_MON] Brutal kill due to lag: ~p~n", [BrutalKill]).

brutal_kill([]) -> ok;
brutal_kill(BrutalKill) -> [erlang:exit(Pid,kill) || Pid <- BrutalKill].


%%-------------------------------------------------------------------------
%% @spec (Reason, State) -> any
%% @doc  Callback executed on server shutdown. It is only invoked if
%%       `process_flag(trap_exit, true)' is set by the server process.
%%       The return value is ignored.
%% @end
%% @private
%%-------------------------------------------------------------------------
terminate(_Reason, _State) ->
  ok.

%%-------------------------------------------------------------------------
%% @spec (OldVsn, State, Extra) -> {ok, NewState}
%% @doc  Convert process state when code is changed.
%% @end
%% @private
%%-------------------------------------------------------------------------
code_change(_OldVsn, State, _Extra) ->
  {ok, State}.

