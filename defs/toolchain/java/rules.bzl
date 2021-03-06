
load(
    "@bazel_tools//tools/build_defs/pkg:pkg.bzl",
    "pkg_tar",
)

load(
    "@rules_java//java:defs.bzl",
    _java_binary = "java_binary",
    _java_library = "java_library",
)

load(
    "@io_bazel_rules_kotlin//kotlin:kotlin.bzl",
    _kt_jvm_binary = "kt_jvm_binary",
    _kt_jvm_library = "kt_jvm_library",
)

load(
    "@io_bazel_rules_docker//java:image.bzl",
    _java_image = "java_image",
)

load(
    "@io_bazel_rules_docker//container:image.bzl",
    _container_image = "container_image",
)

load(
    "@io_bazel_rules_docker//container:push.bzl",
    _container_push = "container_push",
)

load(
    "@rules_graal//graal:graal.bzl",
    _graal_binary = "graal_binary",
)


load(
    "//defs/toolchain:schema.bzl",
    "JAVAPROTO_POSTFIX_",
    "CLOSUREPROTO_POSTFIX_",
)

load(
    "//defs/toolchain/context:props.bzl",
    _annotate_defs_dict = "annotate_defs_dict",
    _annotate_jvm_flags = "annotate_jvm_flags",
)

load(
    "//defs/toolchain:deps.bzl",
    "maven",
)


INJECTED_MICRONAUT_DEPS = [
    "@gust//defs/toolchain/java/plugins:micronaut",
    maven("com.google.guava:guava"),
    maven("com.google.template:soy"),
    maven("com.google.protobuf:protobuf-java"),
    maven("com.google.code.findbugs:jsr305"),
    maven("io.micronaut:micronaut-aop"),
    maven("io.micronaut:micronaut-core"),
    maven("io.micronaut:micronaut-http"),
    maven("io.micronaut:micronaut-http-client"),
    maven("io.micronaut:micronaut-inject"),
    maven("io.micronaut:micronaut-inject-java"),
    maven("io.micronaut:micronaut-validation"),
    maven("io.micronaut:micronaut-http-server"),
    maven("io.micronaut:micronaut-http-server-netty"),
    maven("io.micronaut:micronaut-graal"),
    maven("io.micronaut:micronaut-views"),
    maven("io.micronaut:micronaut-router"),
]

INJECTED_MICRONAUT_RUNTIME_DEPS = [
    maven("org.slf4j:slf4j-jdk14"),
    maven("io.micronaut:micronaut-runtime"),
]


def _dedupe_deps(deps):

    """ Deduplicate a set of string labels in a deps argument. """

    if deps == None:
        return deps
    depindex = []
    for i in deps:
        if i not in depindex:
            depindex.append(i)
    return depindex


def _ensure_types(srcs, ext):

    """ Ensure that all srcs are of a certain file extension, or fail. """

    if any([(not s.endswith(ext)) for s in srcs]):
        fail("All sources must either be Kotlin or Java. " +
             "Expected file extension was '%s'." % ext)


def _jdk_binary(name,
                srcs = [],
                deps = None,
                data = [],
                **kwargs):

    """ Generate a JDK binary, with built-in support for Kotlin. """

    if len(srcs) > 0 and srcs[0].endswith(".kt"):
        # process as kotlin
        _ensure_types(srcs, ".kt")
        _kt_jvm_binary(
            name = name,
            srcs = srcs,
            deps = _dedupe_deps(deps),
            data = data,
            **kwargs
        )

    else:
        # process as java
        _ensure_types(srcs, ".java")
        _java_binary(
            name = name,
            srcs = srcs,
            deps = _dedupe_deps(deps),
            data = data,
            **kwargs
        )


def _jdk_library(name,
                 srcs = [],
                 deps = None,
                 data = [],
                 **kwargs):

    """ Generate a JDK binary, with support for both Java and Kotlin. """

    if len(srcs) > 0 and srcs[0].endswith(".kt"):
        # process as kotlin
        _ensure_types(srcs, ".kt")
        _kt_jvm_library(
            name = name,
            srcs = srcs,
            deps = _dedupe_deps(deps),
            data = data,
            **kwargs
        )

    else:
        # process as java
        _ensure_types(srcs, ".java")
        _java_library(
            name = name,
            srcs = srcs,
            deps = _dedupe_deps(deps),
            data = data,
            **kwargs
        )


def _micronaut_library(name,
                       srcs = [],
                       deps = [],
                       proto_deps = [],
                       runtime_deps = [],
                       data = [],
                       templates = [],
                       exports = [],
                       **kwargs):

    """ Wraps a regular JDK library with injected Micronaut dependencies and plugins. """

    _jdk_library(
        name = name,
        srcs = srcs,
        deps = _dedupe_deps(deps + INJECTED_MICRONAUT_DEPS + [("%s-%s" % (
           p, JAVAPROTO_POSTFIX_
        )) for p in proto_deps] + [
           ("%s-java" % t) for t in templates
        ] + [
           ("%s-java_jcompiled" % t) for t in templates
        ]),
        runtime_deps = _dedupe_deps(runtime_deps + INJECTED_MICRONAUT_RUNTIME_DEPS + [
          ("%s-java" % t) for t in templates
        ] + [
          ("%s-java_jcompiled" % t) for t in templates
        ]),
        exports = _dedupe_deps([("%s-%s" % (
          p, JAVAPROTO_POSTFIX_
        )) for p in proto_deps] + [
          ("%s-java" % t) for t in templates
        ] + [
          ("%s-java_jcompiled" % t) for t in templates
        ] + exports),
        data = data,
        **kwargs
    )


def _micronaut_controller(name,
                          srcs,
                          deps = [],
                          protos = [],
                          templates = [],
                          proto_deps = [],
                          runtime_deps = [],
                          data = [],
                          **kwargs):

    """ Wraps a regular Micronaut JDK library which is intended to be used as a
        controller, potentially with templates to inject. """

    _micronaut_library(
        name = name,
        srcs = srcs,
        proto_deps = protos,
        templates = templates,
        runtime_deps = runtime_deps,
        data = data,
        **kwargs
    )


def _micronaut_native_configset(name, srcs, **kwargs):

    """ Generate a configuration file set which governs reflection or JNI access
        in a native image. """

    native.filegroup(
        name = "%s-files" % name,
        srcs = srcs,
    )

    _java_library(
        name = "%s-lib" % name,
        resources = srcs,
        **kwargs
    )


def _micronaut_application(name,
                           native = False,
                           main_class = "gust.backend.Application",
                           config = str(Label("@gust//java/gust:application.yml")),
                           template_loader = str(Label("@gust//java/gust/backend:TemplateProvider")),
                           logging_config = str(Label("@gust//java/gust:logback.xml")),
                           base = str(Label("@gust//java/gust/backend:base")),
                           native_base = str(Label("@gust//java/gust/backend:native")),
                           native_templates = [],
                           repository = None,
                           native_repository = None,
                           native_configsets = [],
                           registry = "us.gcr.io",
                           image_format = "OCI",
                           srcs = [],
                           controllers = [],
                           tag = None,
                           deps = None,
                           proto_deps = [],
                           data = [],
                           resources = [],
                           runtime_deps = [],
                           jvm_flags = [],
                           defs = {},
                           inject_main = True,
                           reflection_configuration = None,
                           **kwargs):

    """ Wraps a regular JDK application with injected Micronaut dependencies and plugins. """

    computed_jvm_flags = _annotate_jvm_flags([i for i in jvm_flags], defs)

    if len(srcs) > 0:
        computed_deps = _dedupe_deps((deps or []) + INJECTED_MICRONAUT_DEPS + controllers)
        computed_image_deps = _dedupe_deps((deps or []) + INJECTED_MICRONAUT_DEPS)
        computed_image_layers = _dedupe_deps((
            INJECTED_MICRONAUT_RUNTIME_DEPS + [template_loader] + controllers))
        computed_runtime_deps = [template_loader]

        if inject_main:
            computed_deps.append("//java/gust/backend:backend")
    else:
        computed_deps = None
        computed_image_deps = []
        computed_image_layers = []
        computed_runtime_deps = _dedupe_deps(
            (deps or []) +
            INJECTED_MICRONAUT_DEPS +
            controllers + [
                maven("io.micronaut:micronaut-runtime"),
            ] + [template_loader] + [("%s-%s" % (
               p, JAVAPROTO_POSTFIX_
            )) for p in proto_deps] + INJECTED_MICRONAUT_RUNTIME_DEPS + [
               ("%s-java" % t) for t in native_templates
            ] + [
               ("%s-java_jcompiled" % t) for t in native_templates
            ])

        if inject_main:
            computed_runtime_deps.append("//java/gust/backend:backend")

    _java_image(
        name = "%s-image" % name,
        srcs = srcs,
        main_class = main_class,
        deps = computed_image_deps,
        runtime_deps = computed_runtime_deps,
        jvm_flags = computed_jvm_flags + ["-Dgust.engine=jvm"],
        base = base,
        layers = computed_image_layers,
        classpath_resources = [
            config,
            logging_config,
        ],
    )

    _java_library(
        name = "%s-lib" % name,
        srcs = srcs,
        deps = computed_deps,
        runtime_deps = computed_runtime_deps,
        resources = [
            config,
            logging_config,
        ],
        resource_jars = [
            ("%s-lib" % r) for r in native_configsets
        ],
        resource_strip_prefix = "java/gust/",
    )

    if native:
        _graal_binary(
            name = "%s-native" % name,
            deps = _dedupe_deps(["%s-lib" % name] + computed_runtime_deps),
            main_class = main_class,
            c_compiler_path = "/usr/bin/clang",
            configsets = [
                ("%s-files" % c) for c in native_configsets
            ],
            extra_args = [
                # General build flags
                "--no-fallback",

                # Memory usage/runtime flags
                "--no-server",
                "-J-Xms1g",
                "-J-Xmx12g",

                # Extra native-image flags
                "-H:+ParseRuntimeOptions",
                "-H:IncludeResources=application.yml|logback.xml",

                # Build-time init
                "--initialize-at-build-time=com.google.template.soy.jbcsrc.api.RenderResult$Type",
            ] + computed_jvm_flags + ["-Dgust.engine=native"],
            reflection_configuration = reflection_configuration,
        )

        pkg_tar(
            name = "%s-native-pkg" % name,
            extension = "tar",
            srcs = ["%s-native-bin" % name],
        )

        _container_image(
            name = "%s-native-image" % name,
            base = native_base,
            directory = "/app",
            files = ["%s-native-bin" % name],
            workdir = "/app",
            cmd = None,
            env = {
                "PORT": "8080",
                "ENGINE": "native",
            },
            entrypoint = [
                "/app/entrypoint",
            ] + computed_jvm_flags + ["-Dgust.engine=native"],
            symlinks = {
                "/app/entrypoint": "/app/%s-native-bin" % name
            },
        )

        if native_repository != None:
            _container_push(
                name = "%s-native-image-push" % name,
                image = ":%s-native-image" % name,
                tag = tag or "{BUILD_SCM_VERSION}",
                format = image_format,
                repository = native_repository,
                registry = registry,
            )

    if repository != None:
        _container_push(
            name = "%s-image-push" % name,
            image = ":%s-image" % name,
            tag = tag or "{BUILD_SCM_VERSION}",
            format = image_format,
            repository = repository,
            registry = registry,
        )

    _jdk_binary(
        name = name,
        srcs = srcs,
        deps = computed_deps,
        runtime_deps = computed_runtime_deps,
        data = data,
        resources = resources,
        classpath_resources = [config, logging_config],
        main_class = main_class or "gust.backend.Application",
        jvm_flags = computed_jvm_flags,
        **kwargs
    )


## Meant for private use.
dedupe_deps_ = _dedupe_deps
ensure_types_ = _ensure_types

jdk_binary = _jdk_binary
jdk_library = _jdk_library
micronaut_library = _micronaut_library
micronaut_controller = _micronaut_controller
micronaut_application = _micronaut_application
micronaut_native_configset = _micronaut_native_configset
