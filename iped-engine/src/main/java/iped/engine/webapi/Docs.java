package iped.engine.webapi;

import java.io.IOException;
import java.util.Arrays;
import java.util.HashMap;
import java.util.HashSet;
import java.util.Map;
import java.util.Set;

import javax.ws.rs.GET;
import javax.ws.rs.Path;
import javax.ws.rs.PathParam;
import javax.ws.rs.Produces;
import javax.ws.rs.QueryParam;
import javax.ws.rs.core.MediaType;

import org.apache.lucene.document.Document;
import org.apache.lucene.index.IndexableField;

import io.swagger.annotations.Api;
import io.swagger.annotations.ApiOperation;
import iped.data.IIPEDSource;
import iped.engine.webapi.json.DocPropsJSON;

@Api(value = "Documents")
@Path("sources/{sourceID}/docs")
public class Docs {

    @ApiOperation(value = "Get document's properties")
    @GET
    @Path("{id}")
    @Produces(MediaType.APPLICATION_JSON)
    public static DocPropsJSON properties(@PathParam("sourceID") String sourceID, @PathParam("id") int id,
            @QueryParam("field") String fields
    ) throws IOException {
        IIPEDSource source = Sources.getSource(sourceID);
        int luceneID = source.getLuceneId(id);
        Document doc = source.getReader().document(luceneID);

        DocPropsJSON result = new DocPropsJSON();
        result.setSource(sourceID);
        result.setId(id);
        result.setLuceneId(luceneID);

        Map<String, String[]> properties = new HashMap<>();
        Set<String> fieldSet = null;
        if (fields != null && !fields.trim().isEmpty()) {
            fieldSet = new HashSet<>(Arrays.asList(fields.split(",")));
        }

        for (IndexableField f : doc.getFields()) {
            String name = f.name();
            if (fieldSet == null || fieldSet.contains(name)) {
                String[] values = doc.getValues(name);
                properties.put(name, values);
            }
        }
        result.setProperties(properties);

        result.setBookmarks(source.getBookmarks().getBookmarkList(id));
        result.setSelected(source.getBookmarks().isChecked(id));

        return result;
    }
}
