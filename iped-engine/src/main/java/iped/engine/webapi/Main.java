package iped.engine.webapi;

import java.io.IOException;
import java.net.URI;
import java.util.logging.ConsoleHandler;
import java.util.logging.Level;
import java.util.logging.Logger;

import org.glassfish.grizzly.http.server.HttpServer;
import org.glassfish.jersey.grizzly2.httpserver.GrizzlyHttpServerFactory;
import org.glassfish.jersey.server.ResourceConfig;
import org.json.simple.parser.ParseException;

import io.swagger.jaxrs.config.BeanConfig;
import iped.engine.Version;

/**
 * Main class.
 *
 */
public class Main {

    private static final Logger LOGGER = Logger.getLogger(Main.class.getName());

    /**
     * Starts Grizzly HTTP server exposing JAX-RS resources defined in this
     * application.
     * 
     * @return Grizzly HTTP server.
     * @throws IOException
     * @throws ParseException
     */
    public static HttpServer startServer(String host, int port, String urlToAskSources)
            throws IOException, ParseException {
        // create a resource config that scans for JAX-RS resources and providers
        // in gpinf.api package
        String resources = Main.class.getPackageName();
        BeanConfig beanConfig = new BeanConfig();
        beanConfig.setVersion(Version.APP_VERSION);
        beanConfig.setSchemes(new String[] { "http" });
        beanConfig.setBasePath("/");
        beanConfig.setResourcePackage(resources);
        beanConfig.setScan(true);
        final ResourceConfig rc = new ResourceConfig().packages(resources)
                .register(io.swagger.jaxrs.listing.ApiListingResource.class)
                .register(io.swagger.jaxrs.listing.SwaggerSerializers.class);

        Sources.init(urlToAskSources);

        // https://stackoverflow.com/questions/26546373/showing-grizzly-exceptions-in-eclipse-console
        Logger l = Logger.getLogger("org.glassfish.grizzly.http.server.HttpHandler");
        l.setLevel(Level.FINE);
        l.setUseParentHandlers(false);
        ConsoleHandler ch = new ConsoleHandler();
        ch.setLevel(Level.ALL);
        l.addHandler(ch);

        // create and start a new instance of grizzly http server
        // exposing the Jersey application at BASE_URI
        return GrizzlyHttpServerFactory.createHttpServer(URI.create("http://" + host + ":" + port), rc);
    }

    /**
     * Main method.
     * 
     * @param args
     * @throws IOException
     */
    public static void main(String[] args) throws Exception {
        try {
            String host = "0.0.0.0";
            int port = 8080;
            String urlToAskSources = null;

            for (String arg : args) {
                if (arg.startsWith("--host=")) {
                    host = arg.substring("--host=".length());

                } else if (arg.startsWith("--port=")) {
                    port = Integer.parseInt(arg.substring("--port=".length()));

                } else if (arg.startsWith("--sources=")) {
                    urlToAskSources = arg.substring("--sources=".length());

                } else {
                    printHelp();
                    System.exit(-1);
                }
            }
            if (urlToAskSources == null) {
                System.err.println("missing --sources option");
                printHelp();
                System.exit(-1);
            }
            startServer(host, port, urlToAskSources);
            System.out.println(String.format("Jersey app started with WADL available at \n%sapplication.wadl\n",
                    "http://" + host + ":" + port + "/"));
        } catch (Throwable e) {
            LOGGER.log(Level.SEVERE, "Start server failed", e);
            LOGGER.log(Level.SEVERE, "With cause:", e.getCause());
        }
    }

    public static void printHelp() {
        System.out.println("--sources=(URL|Path)\tfile or url with json: {sources: [{id, path}...], configuration}");
        System.out.println("--host=\t\tdefault:0.0.0.0");
        System.out.println("--port=\t\tdefault:8080");
    }
}
