"""
An engine that reads messages from the salt event bus and pushes
them onto a logstash endpoint.

.. versionadded:: 2015.8.0

:configuration:

    Example configuration

    .. code-block:: yaml

        engines:
          - logstash:
              host: log.my_network.com
              port: 5959
              proto: tcp

:depends: logstash
"""

import logging

import salt.utils.event

try:
    import logstash
except ImportError:
    logstash = None

log = logging.getLogger(__name__)

__virtualname__ = "logstash"


def __virtual__():
    return (
        __virtualname__
        if logstash is not None
        else (False, "python-logstash not installed")
    )


def event_bus_context(opts):
    """
    Get the event bus context so we can read events.
    """
    if opts.get("id").endswith("_master"):
        event_bus = salt.utils.event.get_master_event(
            opts, opts["sock_dir"], listen=True
        )
    else:
        event_bus = salt.utils.event.get_event(
            "minion",
            opts=opts,
            sock_dir=opts["sock_dir"],
            listen=True,
        )
    return event_bus


def validate(data):
    """
    Validate the event data and ensure there are no
    conflicts with skip_list
    """
    skip_list = {
        "args",
        "asctime",
        "created",
        "exc_info",
        "exc_text",
        "filename",
        "funcName",
        "id",
        "levelname",
        "levelno",
        "lineno",
        "module",
        "msecs",
        "msecs",
        "message",
        "msg",
        "name",
        "pathname",
        "process",
        "processName",
        "relativeCreated",
        "thread",
        "threadName",
        "extra",
        "auth_token",
        "password",
        "stack_info",
    }

    matches = skip_list.intersection(data)
    for mat in matches:
        if mat in ('password', 'auth_token'):
            _ = data.pop(mat)
            continue
        data[mat + "_"] = data.pop(mat)
    return data


def start(
    host,
    port=5959,
    tag="salt/engine/logstash",
    proto="udp",
    logger_name="python-logstash-logger",
):  # pylint: disable=too-many-locals
    """
    Listen to salt events and forward them to logstash
    """

    logging.setLoggerClass(logging.Logger)
    logging.setLogRecordFactory(logging.LogRecord)

    if isinstance(host, list):
        from random import choice  # pylint: disable=import-outside-toplevel

        host = choice(host)
    if proto == "tcp":
        logstash_handler = logstash.TCPLogstashHandler
    elif proto == "udp":
        logstash_handler = logstash.UDPLogstashHandler
    logstash_logger = logging.getLogger(logger_name)
    logstash_logger.setLevel(logging.INFO)
    handler = logstash_handler(host, port, version=1)
    logstash_logger.addHandler(handler)

    with event_bus_context(__opts__) as event_bus:
        log.debug("Logstash engine started")
        for event in event_bus.iter_events(full=True, auto_reconnect=True):
            if event and "data" in event and "tag" in event:
                tag, data = event["tag"], validate(event["data"])
                logstash_logger.info(tag, extra=data)
